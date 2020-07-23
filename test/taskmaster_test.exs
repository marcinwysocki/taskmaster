defmodule TaskmasterTest do
  use ExUnit.Case

  describe "race/1" do
    test "starts a process and returns a {:ok, pid} tuple" do
      assert {:ok, _pid} = Taskmaster.race([fn -> 1 end, fn -> 2 end])
    end

    test "sends a message with a result of the function that completes first" do
      {:ok, pid} =
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

    test "doesn't send an exit signal to the caller process when one of the functions crashes" do
      Taskmaster.race([fn -> raise ErlangError end])
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
end
