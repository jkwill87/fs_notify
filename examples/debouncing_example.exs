#!/usr/bin/env elixir

# Debouncing example for FSNotify
# Run with: elixir examples/debouncing_example.exs

Mix.install([{:fs_notify, path: "."}])

defmodule DebouncingExample do
  def run do
    # Watch the current directory
    path = File.cwd!()
    
    IO.puts("=== FSNotify Debouncing Comparison Example ===")
    IO.puts("Watching directory: #{path}")
    IO.puts("Try creating, modifying, or deleting files in this directory...")
    IO.puts("Press Ctrl+C to stop\n")
    
    # Start two watchers - one regular, one debounced
    {:ok, regular_watcher} = FSNotify.start_link(path, recursive: true)
    {:ok, debounced_watcher} = FSNotify.start_link(path, recursive: true, debounce_ms: 500)
    
    # Subscribe to both watchers
    FSNotify.subscribe(regular_watcher)
    FSNotify.subscribe(debounced_watcher)
    
    # Listen for events from both watchers
    listen_for_events(regular_watcher, debounced_watcher)
  end
  
  defp listen_for_events(regular_watcher, debounced_watcher) do
    receive do
      {:file_event, ^regular_watcher, {path, events}} ->
        IO.puts("🔄 REGULAR:   #{format_events(events)} #{Path.basename(path)}")
        listen_for_events(regular_watcher, debounced_watcher)
        
      {:file_event, ^debounced_watcher, {path, events}} ->
        IO.puts("✨ DEBOUNCED: #{format_events(events)} #{Path.basename(path)}")
        listen_for_events(regular_watcher, debounced_watcher)
        
      {:file_event, ^regular_watcher, :stop} ->
        IO.puts("Regular watcher stopped")
        listen_for_events(nil, debounced_watcher)
        
      {:file_event, ^debounced_watcher, :stop} ->
        IO.puts("Debounced watcher stopped")
        if regular_watcher, do: listen_for_events(regular_watcher, nil)
        
    after
      1000 ->
        # Continue listening
        listen_for_events(regular_watcher, debounced_watcher)
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

DebouncingExample.run()