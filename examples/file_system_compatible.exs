#!/usr/bin/env elixir

# Example showing FSNotify's compatibility with file_system API
# This code would work with minimal changes when switching between libraries

Mix.install([{:fs_notify_ex, path: "."}])

defmodule FileSystemCompatibleExample do
  @moduledoc """
  This example demonstrates how FSNotify implements the same subscription
  API as the file_system library, making it easy to switch between them.
  """

  def run do
    # Start a file watcher - same pattern as file_system
    {:ok, watcher} = FSNotify.start_link(["/tmp", "/var/log"], recursive: true)
    
    # Subscribe to events - identical to file_system
    FSNotify.subscribe(watcher)
    
    IO.puts("Watching /tmp and /var/log for file system events...")
    IO.puts("This uses the same API as the file_system library!")
    IO.puts("Try creating a file in /tmp to see events\n")
    
    # The message format is identical to file_system
    listen_for_events(watcher)
  end
  
  defp listen_for_events(watcher) do
    receive do
      # Same message format as file_system: {:file_event, pid, {path, events}}
      {:file_event, ^watcher, {path, events}} ->
        IO.puts("[EVENT] Path: #{path}")
        IO.puts("        Events: #{inspect(events)}")
        IO.puts("")
        
        listen_for_events(watcher)
        
      # Same stop message as file_system
      {:file_event, ^watcher, :stop} ->
        IO.puts("[STOP] File watcher stopped")
        
    after
      5000 ->
        IO.puts("No events in the last 5 seconds...")
        listen_for_events(watcher)
    end
  end
end

# Create a test file to demonstrate
spawn(fn ->
  Process.sleep(1000)
  File.write!("/tmp/fs_notify_test_#{:os.system_time(:millisecond)}.txt", "Hello FSNotify!")
  IO.puts("\n>>> Created test file in /tmp\n")
end)

FileSystemCompatibleExample.run()