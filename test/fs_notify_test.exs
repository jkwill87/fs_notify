defmodule FSNotifyTest do
  use ExUnit.Case

  alias FSNotify.Event
  alias FSNotify.Native

  doctest FSNotify

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

  describe "FSNotify with start_link API" do
    test "can start with single path" do
      path = File.cwd!()

      assert {:ok, pid} = FSNotify.start_link(path)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Stop the watcher
      GenServer.stop(pid)
      Process.sleep(10)
      refute Process.alive?(pid)
    end

    test "can start with multiple paths" do
      # Create a temporary directory within the project for testing
      temp_dir = Path.join(File.cwd!(), "test_temp")
      File.mkdir_p!(temp_dir)

      paths = [File.cwd!(), temp_dir]

      assert {:ok, pid} = FSNotify.start_link(paths)
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)

      # Clean up
      File.rm_rf!(temp_dir)
    end

    test "can start with options" do
      path = File.cwd!()

      assert {:ok, pid} = FSNotify.start_link(path, recursive: false)
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "can start with name" do
      path = File.cwd!()

      assert {:ok, pid} = FSNotify.start_link(path, name: TestWatcher)
      assert is_pid(pid)
      assert Process.whereis(TestWatcher) == pid

      GenServer.stop(TestWatcher)
    end

    test "multiple subscribers receive events" do
      path = File.cwd!()
      {:ok, watcher} = FSNotify.start_link(path)

      # Start multiple subscriber processes
      parent = self()

      spawn(fn ->
        FSNotify.subscribe(watcher)

        receive do
          msg -> send(parent, {:subscriber1, msg})
        after
          1000 -> send(parent, {:subscriber1, :timeout})
        end
      end)

      spawn(fn ->
        FSNotify.subscribe(watcher)

        receive do
          msg -> send(parent, {:subscriber2, msg})
        after
          1000 -> send(parent, {:subscriber2, :timeout})
        end
      end)

      # Give subscribers time to subscribe
      Process.sleep(50)

      # Stop the watcher
      GenServer.stop(watcher)

      # Both subscribers should receive the stop message
      assert_receive {:subscriber1, {:file_event, ^watcher, :stop}}, 1000
      assert_receive {:subscriber2, {:file_event, ^watcher, :stop}}, 1000
    end

    test "dead subscribers are removed automatically" do
      path = File.cwd!()
      {:ok, watcher} = FSNotify.start_link(path)

      # Create a subscriber that dies immediately
      spawn(fn ->
        FSNotify.subscribe(watcher)
        # Exit immediately
      end)

      # Give it time to subscribe and die
      Process.sleep(100)

      # Subscribe ourselves
      FSNotify.subscribe(watcher)

      # Stop the watcher - we should still receive the stop message
      GenServer.stop(watcher)
      assert_receive {:file_event, ^watcher, :stop}, 1000
    end
  end
end
