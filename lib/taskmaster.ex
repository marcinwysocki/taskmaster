defmodule Taskmaster do
  @moduledoc """
  A set of convenience functions for concurrent, asynchronous tasks, loosely inspired by JavaScript's Promises.
  """

  use GenServer

  @doc """
  Creates a process, that runs `funs` concurrently and when the first one resolves, sends a `{:race_won, result}` message to the caller.

  Function resolves either by:
    - returning a value, which results in a `{:race_won, value}` message
    - crashing or returning a `{:error, reason}` tuple, which results in a `{:race_interrupted, {:error | :exit, reason}}` message
    - exceeding a `:timeout` options, which results in a `{:race_interrupted, :timeout}` message

  The process created by `race/2` **isn't linked** to the caller process. It terminates after the race is won.

  Options
    * `:timeout` - a timeout for each function (defaults to 5000)

  Example:
      iex(1)> Taskmaster.race([
      ...(1)>         fn ->
      ...(1)>           :one
      ...(1)>         end,
      ...(1)>         fn ->
      ...(1)>           :timer.sleep(200)
      ...(1)>           :two
      ...(1)>         end,
      ...(1)>         fn ->
      ...(1)>           :timer.sleep(300)
      ...(1)>           :three
      ...(1)>         end
      ...(1)>       ])
      {:ok, #PID<0.178.0>}
      iex(2)> flush
      {:race_won, :one}
      :ok

  The process created by `race/2` **isn't linked** to the caller process. It terminates after the race is won,
  by one of the functions either returning a value or crashing.
  """
  @spec race(funs :: [function(), ...], opts :: [timeout: integer()]) :: {:ok, pid}
  def race(funs, opts \\ [])
  def race([], _), do: raise(ArgumentError, message: "funs cannot be an empty list")

  def race(funs, opts) when is_list(funs) do
    method = if opts[:link], do: :link, else: :nolink

    start(method, {:race, funs, opts})
  end

  def init(%{op: op, caller: caller} = state) do
    monitor = Process.monitor(caller)

    GenServer.cast(self(), op)

    {:ok, %{state | monitor: monitor}}
  end

  def handle_cast({:race, funs, opts}, %{caller: caller} = state) do
    message =
      Task.async_stream(
        funs,
        fn fun ->
          try do
            fun.()
          catch
            problem, reason ->
              {problem, reason}
          end
        end,
        ordered: false,
        max_concurrency: length(funs),
        on_timeout: :kill_task,
        timeout: opts[:timeout] || 5000
      )
      |> Stream.take(1)
      |> Enum.map(fn
        {:ok, {problem, _reason} = res} when problem in [:error, :exit] ->
          {:race_interrupted, res}

        {:ok, value} ->
          {:race_won, value}

        {:exit, :timeout} ->
          {:race_interrupted, :timeout}
      end)
      |> List.first()

    send(caller, message)

    {:stop, :normal, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  def handle_info({:DOWN, monitor, :process, _, reason}, %{monitor: monitor} = state) do
    {:stop, reason, %{state | monitor: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp start(:nolink, op) do
    GenServer.start(__MODULE__, %{op: op, caller: self(), monitor: nil})
  end

  defp start(:link, op) do
    GenServer.start_link(__MODULE__, %{op: op, caller: self(), monitor: nil})
  end
end
