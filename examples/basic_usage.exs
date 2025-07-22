#!/usr/bin/env elixir

# Basic usage example for FSNotify
# Run with: elixir examples/basic_usage.exs

Mix.install([{:fs_notify_ex, path: "."}])

defmodule BasicUsageExample do
  def run do
    # Watch the current directory
    path = File.cwd!()
    
    IO.puts("Starting to watch directory: #{path}")
    IO.puts("Try creating, modifying, or deleting files in this directory...")
    IO.puts("Press Ctrl+C to stop\n")
    
    case FSNotify.start_watching(path, recursive: true) do
      {:ok, watcher_pid} ->
        # Subscribe to events
        FSNotify.subscribe(watcher_pid)
        
        # Listen for events
        listen_for_events()
        
        # Clean up
        FSNotify.stop_watching(watcher_pid)
        
      {:error, reason} ->
        IO.puts("Failed to start watching: #{inspect(reason)}")
    end
  end
  
  defp listen_for_events do
    receive do
      {:file_event, event} ->
        case event do
          %FSNotify.Event{kind: kind, path: path, file_type: file_type} ->
            IO.puts("📁 #{format_event_kind(kind)} #{format_file_type(file_type)}: #{path}")
        end
        
        listen_for_events()
        
    after
      1000 ->
        # Continue listening
        listen_for_events()
    end
  end
  
  defp format_event_kind(:created), do: "CREATED"
  defp format_event_kind(:modified), do: "MODIFIED"
  defp format_event_kind(:removed), do: "REMOVED"
  defp format_event_kind(:renamed), do: "RENAMED"
  defp format_event_kind(:other), do: "OTHER"
  defp format_event_kind(:unknown), do: "UNKNOWN"
  
  defp format_file_type(:file), do: "file"
  defp format_file_type(:directory), do: "directory"
  defp format_file_type(:unknown), do: "item"
end

BasicUsageExample.run()