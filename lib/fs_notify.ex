defmodule FSNotify do
  @moduledoc """
  Cross-platform file system notification library for Elixir.

  This library provides a simple interface for watching files and directories
  for changes using the Rust notify library via a NIF (Native Implemented Function).

  ## Usage

      # Start watching a directory
      {:ok, pid} = FSNotify.start_watching("/path/to/watch")
      
      # Subscribe to events
      FSNotify.subscribe(pid)
      
      # Listen for events
      receive do
        {:file_event, event} -> IO.inspect(event)
      end
      
      # Stop watching
      FSNotify.stop_watching(pid)
  """

  alias FSNotify.Watcher

  @doc """
  Start watching a directory or file for changes.

  ## Parameters
  - path: String path to watch
  - opts: Options for watching (default: [recursive: true])

  ## Returns
  {:ok, pid} | {:error, reason}
  """
  def start_watching(path, opts \\ []) do
    opts = Keyword.put_new(opts, :recursive, true)
    Watcher.start_link({path, opts})
  end

  @doc """
  Stop watching a directory or file.

  ## Parameters
  - watcher_pid: PID returned from start_watching

  ## Returns
  :ok
  """
  def stop_watching(watcher_pid) when is_pid(watcher_pid) do
    GenServer.stop(watcher_pid)
  end

  @doc """
  Subscribe to file system events from a watcher.

  ## Parameters
  - watcher_pid: PID returned from start_watching

  ## Returns
  :ok
  """
  def subscribe(watcher_pid) when is_pid(watcher_pid) do
    GenServer.call(watcher_pid, {:subscribe, self()})
  end

  @doc """
  Unsubscribe from file system events.

  ## Parameters
  - watcher_pid: PID returned from start_watching

  ## Returns
  :ok
  """
  def unsubscribe(watcher_pid) when is_pid(watcher_pid) do
    GenServer.call(watcher_pid, {:unsubscribe, self()})
  end
end
