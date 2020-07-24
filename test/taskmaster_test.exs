defmodule TaskmasterTest do
  use ExUnit.Case

  describe "race/2" do
    test "starts a process and returns a {:ok, pid} tuple" do
      assert {:ok, _pid} = Taskmaster.race([fn -> 1 end, fn -> 2 end])
    end

    test "started process isn't linked to the caller by default" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Taskmaster.race([fn -> 1 end, fn -> 2 end])
      Process.exit(pid, :kill)

      refute_receive {:EXIT, _, _}
    end

    test "started process is linked to the caller if :link option is set to true" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Taskmaster.race([fn -> 1 end, fn -> 2 end], link: true)
      Process.exit(pid, :kill)

      assert_receive {:EXIT, ^pid, :killed}
    end

    test "raises if funs is an empty list" do
      assert_raise ArgumentError, fn -> Taskmaster.race([]) end
    end

    test "sends a message with a result of the function that completes first" do
      Taskmaster.race([
        fn ->
          :one
        end,
        fn ->
          :timer.sleep(200)
          :two
        end,
        fn ->
          :timer.sleep(300)
          :three
        end
      ])

      assert_receive {:race_won, :one}
    end

    test "terminates the functions that lost the race" do
      test_process = self()

      Taskmaster.race([
        fn ->
          :one
        end,
        fn ->
          :timer.sleep(200)
          send(test_process, :fun_two)
          :two
        end,
        fn ->
          :timer.sleep(300)
          send(test_process, :fun_three)
          :three
        end
      ])

      refute_receive :two
      refute_receive :fun_two
      refute_receive :three
      refute_receive :fun_three
    end

    test "returns an error as a result, if the winning function crashes" do
      Taskmaster.race([
        fn ->
          raise ErlangError
        end,
        fn ->
          :timer.sleep(200)
          :two
        end,
        fn ->
          :timer.sleep(300)
          :three
        end
      ])

      assert_receive {:race_interrupted, {:error, %ErlangError{}}}
    end

    test "returns an error, if the winning function returns an error tuple" do
      Taskmaster.race([
        fn ->
          :timer.sleep(100)
          :one
        end,
        fn ->
          {:error, :reason}
        end,
        fn ->
          :timer.sleep(300)
          :three
        end
      ])

      assert_receive {:race_interrupted, {:error, :reason}}
    end

    test "returns :timeout as a result, if the fastest function still exceeds the :timeout option" do
      Taskmaster.race(
        [
          fn ->
            :timer.sleep(1000)
            :one
          end,
          fn ->
            :timer.sleep(2000)
            :two
          end,
          fn ->
            :timer.sleep(3000)
            :three
          end
        ],
        timeout: 50
      )

      assert_receive {:race_interrupted, :timeout}
    end
  end

  describe "all/2" do
    test "starts a process and returns a {:ok, pid} tuple" do
      assert {:ok, _pid} = Taskmaster.all([fn -> 1 end, fn -> 2 end])
    end

    test "started process isn't linked to the caller by default" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Taskmaster.all([fn -> 1 end, fn -> 2 end])
      Process.exit(pid, :kill)

      refute_receive {:EXIT, _, _}
    end

    test "started process is linked to the caller if :link option is set to true" do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Taskmaster.all([fn -> 1 end, fn -> 2 end], link: true)
      Process.exit(pid, :kill)

      assert_receive {:EXIT, ^pid, :killed}
    end

    test "raises if funs is an empty list" do
      assert_raise ArgumentError, fn -> Taskmaster.all([]) end
    end

    test "sends a message with all return values (in order) to the caller after all the funs return" do
      test_process = self()

      Taskmaster.all([
        fn ->
          :one
        end,
        fn ->
          :timer.sleep(200)
          send(test_process, :fun_two)
          :two
        end,
        fn ->
          :timer.sleep(100)
          send(test_process, :fun_three)
          :three
        end
      ])

      refute_received {:all_return_values, [:one, :two, :three]}
      assert_receive {:all_return_values, [:one, :two, :three]}, 400
    end

    test "sends an error message to the caller if one of the functions raises en error" do
      Taskmaster.all([
        fn ->
          :one
        end,
        fn ->
          :timer.sleep(200)
          raise ErlangError
        end,
        fn ->
          :timer.sleep(300)
          :three
        end
      ])

      assert_receive {:all_error, {:error, %ErlangError{}}}, 500
    end

    test "sends an error message to the caller if one of the functions retuns an error tuple" do
      Taskmaster.all([
        fn ->
          :one
        end,
        fn ->
          :timer.sleep(100)
          :two
        end,
        fn ->
          :timer.sleep(200)
          {:error, :reason}
        end
      ])

      assert_receive {:all_error, {:error, reason}}, 500
    end

    test "sends an error message to the caller if one of the functions times out" do
      Taskmaster.all(
        [
          fn ->
            :one
          end,
          fn ->
            :timer.sleep(50)
            :two
          end,
          fn ->
            :timer.sleep(200)
            :three
          end
        ],
        timeout: 100
      )

      assert_receive {:all_error, {:exit, :timeout}}, 500
    end
  end
end
