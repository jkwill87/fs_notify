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
# Start watching a directory
{:ok, watcher_pid} = FSNotify.start_watching("/path/to/watch")

# Subscribe to events
FSNotify.subscribe(watcher_pid)

# Listen for events
receive do
  {:file_event, %FSNotify.Event{kind: kind, path: path, file_type: file_type}} ->
    IO.puts("#{kind} #{file_type}: #{path}")
end

# Stop watching
FSNotify.stop_watching(watcher_pid)
```

### Options

```elixir
# Watch recursively (default)
{:ok, pid} = FSNotify.start_watching("/path", recursive: true)

# Watch only the specific directory, not subdirectories
{:ok, pid} = FSNotify.start_watching("/path", recursive: false)
```

### Event Types

Events are delivered as `%FSNotify.Event{}` structs with the following fields:

- `kind`: `:created`, `:modified`, `:removed`, `:renamed`, `:other`, or `:unknown`
- `path`: String path of the affected file or directory
- `file_type`: `:file`, `:directory`, or `:unknown`

### Helper Functions

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
