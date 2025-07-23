defmodule FSNotify.Watcher do
  @moduledoc """
  GenServer that manages file system watching and event distribution.
  """

  use GenServer

  alias FSNotify.Event
  alias FSNotify.Native

  require Logger

  defstruct paths: [],
            watchers: %{},
            recursive: true,
            backend: :recommended,
            debounce_ms: nil,
            subscribers: %{}

  @type t :: %__MODULE__{
          paths: [String.t()],
          watchers: %{String.t() => non_neg_integer()},
          recursive: boolean(),
          backend: atom(),
          debounce_ms: non_neg_integer() | nil,
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
    backend = Keyword.get(opts, :backend, :recommended)
    debounce_ms = Keyword.get(opts, :debounce_ms)

    # Start watchers for each path
    watchers =
      paths
      |> Enum.map(fn path ->
        case start_watcher_for_backend(path, recursive, backend, debounce_ms) do
          {:ok, watcher_id} ->
            debounce_info = if debounce_ms, do: ", debounce: #{debounce_ms}ms", else: ""

            Logger.debug(
              "Started file watcher for path: #{path} (recursive: #{recursive}, backend: #{backend}#{debounce_info})"
            )

            {path, watcher_id}

          {:error, reason} ->
            Logger.error("Failed to start file watcher for path: #{path}, reason: #{inspect(reason)}")

            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    if map_size(watchers) == 0 do
      {:stop, :no_watchers_started}
    else
      state = %__MODULE__{
        paths: paths,
        watchers: watchers,
        recursive: recursive,
        backend: backend,
        debounce_ms: debounce_ms,
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
    Enum.each(state.watchers, fn {_path, watcher_id} ->
      case Native.get_events(watcher_id) do
        events when is_list(events) ->
          # Convert raw events to Event structs and broadcast
          events
          |> Enum.map(&Event.from_tuple/1)
          |> Enum.each(fn event ->
            broadcast_event(state.subscribers, event)
          end)

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

    Logger.debug("Stopped file watchers for paths: #{inspect(state.paths)}")
    :ok
  end

  # Private functions

  defp start_watcher_for_backend(path, recursive, backend, nil) do
    # No debouncing - use regular watcher
    case backend do
      :recommended -> Native.start_watcher(path, recursive)
      _ -> Native.start_watcher_with_backend(path, recursive, backend)
    end
  end

  defp start_watcher_for_backend(path, recursive, backend, debounce_ms) when is_integer(debounce_ms) do
    # Debouncing enabled - use debounced watcher
    Native.start_watcher_with_debounce(path, recursive, backend, debounce_ms)
  end

  defp schedule_event_polling do
    # Poll every 100ms for events
    Process.send_after(self(), :poll_events, 100)
  end

  defp broadcast_event(subscribers, %Event{} = event) do
    event_data = {event.path, [event.kind]}

    subscribers
    |> Map.values()
    |> Enum.each(fn pid ->
      send(pid, {:file_event, self(), event_data})
    end)
  end
end
