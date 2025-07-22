defmodule FSNotifyTest do
  use ExUnit.Case
  doctest FSNotify

  alias FSNotify.{Native, Event}

  describe "FSNotify.Native" do
    test "can start and stop a watcher" do
      # Test with current directory
      path = File.cwd!()

      case Native.start_watcher(path, true) do
        {:ok, watcher_id} ->
          assert is_integer(watcher_id)
          assert watcher_id > 0

          # Test stopping the watcher
          assert Native.stop_watcher(watcher_id) == :ok

        {:error, _reason} ->
          flunk("Failed to start watcher")
      end
    end

    test "can get events from a watcher" do
      path = File.cwd!()

      case Native.start_watcher(path, true) do
        {:ok, watcher_id} ->
          # Events should be empty initially
          case Native.get_events(watcher_id) do
            {:ok, events} ->
              assert is_list(events)

            [] ->
              # Empty list is also acceptable
              assert true

            result ->
              flunk("Unexpected result: #{inspect(result)}")
          end

          Native.stop_watcher(watcher_id)

        {:error, _reason} ->
          flunk("Failed to start watcher")
      end
    end
  end

  describe "FSNotify.Event" do
    test "can create event from tuple" do
      event_tuple = {:created, "/test/path", :file}
      event = Event.from_tuple(event_tuple)

      assert %Event{} = event
      assert event.kind == :created
      assert event.path == "/test/path"
      assert event.file_type == :file
    end

    test "event type predicates work correctly" do
      created_event = %Event{kind: :created, path: "/test", file_type: :file}
      modified_event = %Event{kind: :modified, path: "/test", file_type: :directory}

      assert Event.created?(created_event)
      refute Event.created?(modified_event)

      assert Event.modified?(modified_event)
      refute Event.modified?(created_event)

      assert Event.file?(created_event)
      refute Event.file?(modified_event)

      assert Event.directory?(modified_event)
      refute Event.directory?(created_event)
    end
  end

  describe "FSNotify" do
    test "can start and stop watching" do
      path = File.cwd!()

      case FSNotify.start_watching(path) do
        {:ok, pid} ->
          assert is_pid(pid)
          assert Process.alive?(pid)

          # Test stopping
          assert :ok = FSNotify.stop_watching(pid)

          # Give it a moment to stop
          Process.sleep(10)
          refute Process.alive?(pid)

        {:error, reason} ->
          flunk("Failed to start watching: #{inspect(reason)}")
      end
    end

    test "can subscribe and unsubscribe" do
      path = File.cwd!()

      case FSNotify.start_watching(path) do
        {:ok, pid} ->
          assert :ok = FSNotify.subscribe(pid)
          assert :ok = FSNotify.unsubscribe(pid)

          FSNotify.stop_watching(pid)

        {:error, reason} ->
          flunk("Failed to start watching: #{inspect(reason)}")
      end
    end
  end
end
