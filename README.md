# fs_notify_ex

Cross-platform file system notification library for Elixir.

FSNotify provides a simple interface for watching files and directories for changes across different operating systems. It uses Rustler to create a NIF (Native Implemented Function) that leverages the high-performance Rust notify library.

## Features

- **Cross-platform**: Works on Linux, macOS, Windows, and other supported platforms
- **High performance**: Uses Rust's notify library for efficient file watching
- **GenServer integration**: Clean Elixir GenServer API for managing watchers
- **Event filtering**: Subscribe to specific types of file system events
- **Recursive watching**: Monitor entire directory trees or individual files

## Installation

Add `fs_notify_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:fs_notify_ex, "~> 0.1.0"}
  ]
end
```

**Note**: This library requires Rust to be installed for compilation.

## Usage

### Basic Example

```elixir
# Start watching a single directory
{:ok, watcher} = FSNotify.start_link("/path/to/watch")

# Start watching multiple directories
{:ok, watcher} = FSNotify.start_link(["/path1", "/path2"])

# With options
{:ok, watcher} = FSNotify.start_link("/path", recursive: false, name: MyWatcher)

# Subscribe to events
FSNotify.subscribe(watcher)

# Listen for events
receive do
  {:file_event, ^watcher, {path, events}} ->
    IO.puts("Events #{inspect(events)} occurred on #{path}")
  {:file_event, ^watcher, :stop} ->
    IO.puts("Watcher stopped")
end

# Stop watching
GenServer.stop(watcher)
```

### Options

```elixir
# Watch recursively (default: true)
{:ok, pid} = FSNotify.start_link("/path", recursive: true)

# Watch only the specific directory, not subdirectories
{:ok, pid} = FSNotify.start_link("/path", recursive: false)

# Named process
{:ok, pid} = FSNotify.start_link("/path", name: MyFileWatcher)
```

### Event Types

Events are delivered as lists of atoms in the message tuple `{path, events}`:

| Event Type | Description |
|------------|-------------|
| `:created` | File or directory was created |
| `:modified` | File or directory was modified |
| `:removed` | File or directory was removed |
| `:renamed` | File or directory was renamed |
| `:other` | Other events |
| `:unknown` | Unknown event type |

### Internal Event Structure

Internally, FSNotify uses `%FSNotify.Event{}` structs with helper functions:

```elixir
event = %FSNotify.Event{kind: :created, path: "/test.txt", file_type: :file}

FSNotify.Event.created?(event)   # true
FSNotify.Event.file?(event)      # true
FSNotify.Event.directory?(event) # false
```

## Requirements

- Elixir 1.18+
- Rust toolchain (for compilation)
- Supported operating systems: Linux, macOS, Windows, BSD variants

## Architecture

FSNotify consists of three main components:

1. **Rust NIF**: Uses the notify library to provide low-level file watching
2. **GenServer Watcher**: Manages file watchers and event distribution
3. **Event Types**: Structured representation of file system events

## Examples

See the `examples/` directory for more usage examples.

## License

This project is licensed under the MIT License.
