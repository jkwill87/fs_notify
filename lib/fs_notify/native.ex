defmodule FSNotify.Native do
  @moduledoc """
  NIF module for file system notification using Rust notify library.
  """

  use Rustler, otp_app: :fs_notify, crate: "fs_notify"

  @doc """
  Start watching a directory or file.

  ## Parameters
  - path: String path to watch
  - recursive: Boolean indicating whether to watch recursively

  ## Returns
  {:ok, watcher_id} or {:error, reason}
  """
  def start_watcher(_path, _recursive), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Stop a file watcher.

  ## Parameters
  - watcher_id: ID returned from start_watcher

  ## Returns
  :ok
  """
  def stop_watcher(_watcher_id), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Get events from a watcher.

  ## Parameters
  - watcher_id: ID returned from start_watcher

  ## Returns
  List of events in format [{event_type, path, file_type}]
  """
  def get_events(_watcher_id), do: :erlang.nif_error(:nif_not_loaded)
end
