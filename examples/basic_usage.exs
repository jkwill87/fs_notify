#!/usr/bin/env elixir

# Basic usage example for FSNotify
# Run with: elixir examples/basic_usage.exs

Mix.install([{:fs_notify, path: "."}])

defmodule BasicUsageExample do
  def run do
    # Watch the current directory
    path = File.cwd!()
    
    IO.puts("Starting to watch directory: #{path}")
    IO.puts("Try creating, modifying, or deleting files in this directory...")
    IO.puts("Press Ctrl+C to stop\n")
    
    case FSNotify.start_link(path, recursive: true) do
      {:ok, watcher_pid} ->
        # Subscribe to events
        FSNotify.subscribe(watcher_pid)
        
        # Listen for events
        listen_for_events(watcher_pid)
        
      {:error, reason} ->
        IO.puts("Failed to start watching: #{inspect(reason)}")
    end
  end
  
  defp listen_for_events(watcher_pid) do
    receive do
      {:file_event, ^watcher_pid, {path, events}} ->
        IO.puts("📁 #{format_events(events)} #{path}")
        listen_for_events(watcher_pid)
        
      {:file_event, ^watcher_pid, :stop} ->
        IO.puts("Watcher stopped")
        
    after
      1000 ->
        # Continue listening
        listen_for_events(watcher_pid)
    end
  end
  
  defp format_events(events) do
    events
    |> Enum.map(&format_event_kind/1)
    |> Enum.join(", ")
  end
  
  defp format_event_kind(:created), do: "CREATED"
  defp format_event_kind(:modified), do: "MODIFIED"
  defp format_event_kind(:removed), do: "REMOVED"
  defp format_event_kind(:renamed), do: "RENAMED"
  defp format_event_kind(:other), do: "OTHER"
  defp format_event_kind(:unknown), do: "UNKNOWN"
end

BasicUsageExample.run()