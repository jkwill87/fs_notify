defmodule FSNotify do
  @moduledoc """
  Cross-platform file system notification library for Elixir.

  This library provides a simple interface for watching files and directories
  for changes using the Rust notify library via a NIF (Native Implemented Function).

  ## Usage

      # Start watching a single directory
      {:ok, pid} = FSNotify.start_link("/path/to/watch")
      
      # Start watching multiple directories
      {:ok, pid} = FSNotify.start_link(["/path1", "/path2"])
      
      # With options
      {:ok, pid} = FSNotify.start_link("/path", recursive: false, name: MyWatcher)
      
      # Subscribe to events
      FSNotify.subscribe(pid)
      
      # Listen for events
      receive do
        {:file_event, ^pid, {path, events}} -> 
          IO.puts("Events \#{inspect(events)} on \#{path}")
        {:file_event, ^pid, :stop} ->
          IO.puts("Watcher stopped")
      end
  """

  alias FSNotify.Watcher

  @type path_spec :: String.t() | [String.t()]
  @type start_options :: [start_option()]
  @type start_option ::
          {:recursive, boolean()}
          | {:name, GenServer.name()}
          | {:backend, atom()}

  @doc """
  Starts a file system watcher process.

  ## Parameters
  - `path_or_paths` - A single path string or a list of path strings to watch
  - `options` - Keyword list of options:
    - `:recursive` - Whether to watch subdirectories (default: `true`)
    - `:name` - A name to register the process under
    - `:backend` - Backend to use (default: `:fs_notify`)

  ## Examples

      # Single path
      {:ok, pid} = FSNotify.start_link("/tmp")
      
      # Multiple paths
      {:ok, pid} = FSNotify.start_link(["/tmp", "/var/log"])
      
      # With options
      {:ok, pid} = FSNotify.start_link("/home", recursive: false)
      {:ok, pid} = FSNotify.start_link("/tmp", name: TmpWatcher)

  ## Returns
  - `{:ok, pid}` on success
  - `{:error, reason}` on failure
  """
  @spec start_link(path_spec(), start_options()) :: GenServer.on_start()
  def start_link(path_or_paths, options \\ [])

  def start_link(path_or_paths, options) do
    {name_opts, other_opts} = Keyword.split(options, [:name])
    start_opts = if name_opts[:name], do: [name: name_opts[:name]], else: []
    
    Watcher.start_link({path_or_paths, other_opts}, start_opts)
  end

  @doc """
  Subscribe the calling process to file system events.

  The subscribed process will receive messages in the format:
  - `{:file_event, watcher_pid, {path, events}}` - for file system events
  - `{:file_event, watcher_pid, :stop}` - when the watcher stops

  ## Parameters
  - `watcher` - The watcher process (pid or name)

  ## Returns
  - `:ok`
  """
  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(watcher) do
    GenServer.call(watcher, :subscribe)
  end
end
