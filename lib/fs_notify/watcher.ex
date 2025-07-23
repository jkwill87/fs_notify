defmodule FSNotify.Watcher do
  @moduledoc """
  GenServer that manages file system watching and event distribution.
  """

  use GenServer
  require Logger

  alias FSNotify.{Native, Event}

  defstruct [
    paths: [],
    watchers: %{},
    recursive: true,
    subscribers: %{}
  ]

  @type t :: %__MODULE__{
          paths: [String.t()],
          watchers: %{String.t() => non_neg_integer()},
          recursive: boolean(),
          subscribers: %{reference() => pid()}
        }

  # Client API

  @doc """
  Start a new watcher GenServer.
  """
  def start_link({path_or_paths, opts}, genserver_opts \\ []) do
    GenServer.start_link(__MODULE__, {path_or_paths, opts}, genserver_opts)
  end

  # Server Callbacks

  @impl true
  def init({path_or_paths, opts}) do
    paths = List.wrap(path_or_paths)
    recursive = Keyword.get(opts, :recursive, true)
    
    # Start watchers for each path
    watchers = 
      paths
      |> Enum.map(fn path ->
        case Native.start_watcher(path, recursive) do
          {:ok, watcher_id} ->
            Logger.info("Started file watcher for path: #{path} (recursive: #{recursive})")
            {path, watcher_id}
          {:error, reason} ->
            Logger.error("Failed to start file watcher for path: #{path}, reason: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.into(%{})

    if map_size(watchers) == 0 do
      {:stop, :no_watchers_started}
    else
      state = %__MODULE__{
        paths: paths,
        watchers: watchers,
        recursive: recursive,
        subscribers: %{}
      }

      # Schedule periodic event polling
      schedule_event_polling()

      {:ok, state}
    end
  end

  @impl true
  def handle_call(:subscribe, {pid, _tag}, state) do
    ref = Process.monitor(pid)
    new_subscribers = Map.put(state.subscribers, ref, pid)
    new_state = %{state | subscribers: new_subscribers}

    Logger.debug("Process #{inspect(pid)} subscribed to file events")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:poll_events, state) do
    # Poll for events from all native watchers
    state.watchers
    |> Enum.each(fn {_path, watcher_id} ->
      case Native.get_events(watcher_id) do
        {:ok, events} ->
          # Convert raw events to Event structs and broadcast
          events
          |> Enum.map(&Event.from_tuple/1)
          |> Enum.each(fn event ->
            broadcast_event(state.subscribers, event)
          end)

        [] ->
          # No events, which is fine
          :ok

        {:error, reason} ->
          Logger.error("Failed to get events from watcher: #{inspect(reason)}")
      end
    end)

    # Schedule next polling
    schedule_event_polling()

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    # Remove the dead process from subscribers
    new_subscribers = Map.delete(state.subscribers, ref)
    new_state = %{state | subscribers: new_subscribers}

    Logger.debug("Removed dead subscriber")
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Broadcast stop message to all subscribers
    state.subscribers
    |> Map.values()
    |> Enum.each(fn pid ->
      send(pid, {:file_event, self(), :stop})
    end)

    # Stop all watchers
    state.watchers
    |> Map.values()
    |> Enum.each(&Native.stop_watcher/1)

    Logger.info("Stopped file watchers for paths: #{inspect(state.paths)}")
    :ok
  end

  # Private functions

  defp schedule_event_polling do
    # Poll every 100ms for events
    Process.send_after(self(), :poll_events, 100)
  end

  defp broadcast_event(subscribers, %Event{} = event) do
    # Convert event to file_system compatible format
    # Group by path to match file_system's {path, events} format
    event_data = {event.path, [event.kind]}
    
    subscribers
    |> Map.values()
    |> Enum.each(fn pid ->
      send(pid, {:file_event, self(), event_data})
    end)
  end
end