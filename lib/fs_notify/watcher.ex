defmodule FSNotify.Watcher do
  @moduledoc """
  GenServer that manages file system watching and event distribution.
  """

  use GenServer
  require Logger

  alias FSNotify.{Native, Event}

  defstruct [
    :path,
    :watcher_id,
    :recursive,
    subscribers: MapSet.new()
  ]

  @type t :: %__MODULE__{
          path: String.t(),
          watcher_id: non_neg_integer() | nil,
          recursive: boolean(),
          subscribers: MapSet.t(pid())
        }

  # Client API

  @doc """
  Start a new watcher GenServer.
  """
  def start_link({path, opts}) do
    GenServer.start_link(__MODULE__, {path, opts})
  end

  @doc """
  Start a new watcher GenServer with a name.
  """
  def start_link({path, opts}, name) do
    GenServer.start_link(__MODULE__, {path, opts}, name: name)
  end

  # Server Callbacks

  @impl true
  def init({path, opts}) do
    recursive = Keyword.get(opts, :recursive, true)

    case Native.start_watcher(path, recursive) do
      {:ok, watcher_id} ->
        state = %__MODULE__{
          path: path,
          watcher_id: watcher_id,
          recursive: recursive
        }

        Logger.info("Started file watcher for path: #{path} (recursive: #{recursive})")

        # Schedule periodic event polling
        schedule_event_polling()

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start file watcher for path: #{path}, reason: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:subscribe, pid}, _from, state) do
    new_subscribers = MapSet.put(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}

    # Monitor the subscribing process
    Process.monitor(pid)

    Logger.debug("Process #{inspect(pid)} subscribed to file events")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unsubscribe, pid}, _from, state) do
    new_subscribers = MapSet.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}

    Logger.debug("Process #{inspect(pid)} unsubscribed from file events")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:poll_events, state) do
    # Poll for events from the native watcher
    case Native.get_events(state.watcher_id) do
      {:ok, events} ->
        # Convert raw events to Event structs and send to subscribers
        events
        |> Enum.map(&Event.from_tuple/1)
        |> Enum.each(fn event ->
          broadcast_event(state.subscribers, event)
        end)

      {:error, reason} ->
        Logger.error("Failed to get events from watcher: #{inspect(reason)}")
    end

    # Schedule next polling
    schedule_event_polling()

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove the dead process from subscribers
    new_subscribers = MapSet.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}

    Logger.debug("Removed dead process #{inspect(pid)} from subscribers")
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.watcher_id do
      Native.stop_watcher(state.watcher_id)
      Logger.info("Stopped file watcher for path: #{state.path}")
    end

    :ok
  end

  # Private functions

  defp schedule_event_polling do
    # Poll every 100ms for events
    Process.send_after(self(), :poll_events, 100)
  end

  defp broadcast_event(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:file_event, event})
    end)
  end
end
