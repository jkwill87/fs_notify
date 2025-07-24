defmodule FSNotify.Event do
  @moduledoc """
  Defines the structure and types for file system events.
  """

  @type event_kind :: :created | :modified | :removed | :renamed | :meta | :unknown
  @type file_type :: :file | :directory | :unknown

  @type t :: %__MODULE__{
          kind: event_kind(),
          path: String.t(),
          file_type: file_type()
        }

  defstruct [:kind, :path, :file_type]

  @doc """
  Create a new event struct from the tuple format returned by the NIF.

  ## Parameters
  - {kind, path, file_type}: Tuple from the Rust NIF

  ## Returns
  %FSNotify.Event{}
  """
  def from_tuple({kind, path, file_type}) do
    %__MODULE__{
      kind: kind,
      path: path,
      file_type: file_type
    }
  end

  @doc """
  Check if an event indicates a file was created.
  """
  def created?(%__MODULE__{kind: :created}), do: true
  def created?(_), do: false

  @doc """
  Check if an event indicates a file was modified.
  """
  def modified?(%__MODULE__{kind: :modified}), do: true
  def modified?(_), do: false

  @doc """
  Check if an event indicates a file was removed.
  """
  def removed?(%__MODULE__{kind: :removed}), do: true
  def removed?(_), do: false

  @doc """
  Check if an event indicates a file was renamed.
  """
  def renamed?(%__MODULE__{kind: :renamed}), do: true
  def renamed?(_), do: false

  @doc """
  Check if the event is for a file (not a directory).
  """
  def file?(%__MODULE__{file_type: :file}), do: true
  def file?(_), do: false

  @doc """
  Check if the event is for a directory.
  """
  def directory?(%__MODULE__{file_type: :directory}), do: true
  def directory?(_), do: false
end
