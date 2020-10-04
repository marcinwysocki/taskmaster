defmodule Taskmaster do
  @moduledoc """
  A set of convenience functions for concurrent, asynchronous tasks, loosely inspired by JavaScript's Promises.

  ## Why?

  While Elixir's `Task` module provides an API for easy creation of concurrent processes, it does so by *blocking* the caller process on calls to `Task.await/2` or `Task.async_stream/3`. However, sometimes it is
  beneficial to operate asynchronously, in a manner somewhat similar to JavaScript's Promises - let the work be done in the background and then  act on the results when everything is resolved.

  `Taskmaster` wraps around the built-in `Task` module to provide a set of useful functions for doing just that.
  """

  @doc false
  use GenServer

  defguardp is_error(tuple) when tuple_size(tuple) === 2 and elem(tuple, 0) in [:exit, :error]

  @type options :: [timeout: non_neg_integer(), link: boolean() | nil]

  @doc """
  Creates a process, that runs `funs` concurrently and when the first one resolves, sends a message to the caller.

  Function resolves either by:
    - returning a value, which results in a `{:race_won, value}` message
    - crashing or returning a `{:error, reason}` tuple, which results in a `{:race_interrupted, {:error | :exit, reason}}` message
    - exceeding a `:timeout` options, which results in a `{:race_interrupted, :timeout}` message

  The process created by `race/2` **by default isn't linked** to the caller process. It can be started as a linked process by passing a `link: true` option.

  Options
    * `:timeout` - a timeout for each function (defaults to 5000)
    * `:link` - should the started process by linked to the caller (defaults to `false`)

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
  """
  @spec race(funs :: [function(), ...], opts :: options()) ::
          {:ok, pid}
  def race(funs, opts \\ [])
  def race([], _), do: raise(ArgumentError, message: "funs cannot be an empty list")
  def race(funs, opts) when is_list(funs), do: do_start(opts, {:"$taskmaster_race", funs, opts})

  @doc """
  Creates a process, that runs `funs` concurrently and sends a message to the caller when all of them either return a value or one of them either crashes or returns an error.

  Possible messages:
    - `{:all_results, results}` when all the `funs` return a result
    - `{:all_error, error}` when either function:
      - returns an `{:error, reason}`
      - crashes
      - exceeds a `:timeout` option

  The process created by `all/2` **by default isn't linked** to the caller process. It can be started as a linked process by passing a `link: true` option.

  Options
    * `:timeout` - a timeout for each function (defaults to 5000)
    * `:link` - should the started process by linked to the caller (defaults to `false`)

  Example:
      iex(1)> Taskmaster.all(
      ...(1)>   [
      ...(1)>     fn ->
      ...(1)>       :one
      ...(1)>     end,
      ...(1)>     fn ->
      ...(1)>       :timer.sleep(50)
      ...(1)>       :two
      ...(1)>     end,
      ...(1)>     fn ->
      ...(1)>       :timer.sleep(200)
      ...(1)>       :three
      ...(1)>     end
      ...(1)>   ],
      ...(1)>   timeout: 1000
      ...(1)> )
      {:ok, #PID<0.216.0>}
      iex(2)> flush()
      {:all_return_values, [:one, :two, :three]}
      :ok
  """
  @spec all(funs :: [function(), ...], opts :: options()) :: {:ok, pid}
  def all(funs, opts \\ [])
  def all([], _), do: raise(ArgumentError, message: "funs cannot be an empty list")
  def all(funs, opts) when is_list(funs), do: do_start(opts, {:"$taskmaster_all", funs, opts})

  @doc false
  @impl true
  def init(%{op: op, caller: caller} = state) do
    monitor = Process.monitor(caller)

    GenServer.cast(self(), op)

    {:ok, %{state | monitor: monitor}}
  end

  @impl true
  def handle_cast({:"$taskmaster_all", funs, opts}, %{caller: caller} = state) do
    funs_results =
      funs
      |> run_concurrently(ordered: true, timeout: opts[:timeout])
      |> values()
      |> results_if_all(&correct_result?/1)

    result =
      case funs_results do
        [error] when is_error(error) -> {:error, error}
        elements -> elements
      end

    send(caller, %Taskmaster.Result{action: :all, result: result})

    {:stop, :normal, state}
  end

  def handle_cast({:"$taskmaster_race", funs, opts}, %{caller: caller} = state) do
    funs_result =
      funs
      |> run_concurrently(ordered: false, timeout: opts[:timeout])
      |> values()
      |> Stream.take(1)
      |> extract()
      |> List.first()

    result =
      case funs_result do
        {:exit, :timeout} -> {:interrupted, :timeout}
        error when is_error(error) -> {:interrupted, error}
        value -> {:winner, value}
      end

    send(caller, %Taskmaster.Result{action: :race, result: result})

    {:stop, :normal, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl true
  def handle_info({:DOWN, monitor, :process, _, reason}, %{monitor: monitor} = state) do
    {:stop, reason, %{state | monitor: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp do_start(opts, op) when is_list(opts) do
    method = if opts[:link], do: :link, else: :nolink

    do_start(method, op)
  end

  defp do_start(:nolink, op) do
    GenServer.start(__MODULE__, %{op: op, caller: self(), monitor: nil})
  end

  defp do_start(:link, op) do
    GenServer.start_link(__MODULE__, %{op: op, caller: self(), monitor: nil})
  end

  defp run_concurrently(funs, opts) do
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
      ordered: opts[:ordered],
      max_concurrency: length(funs),
      on_timeout: :kill_task,
      timeout: opts[:timeout] || 5000
    )
  end

  defp values(stream) do
    Stream.map(stream, fn
      {:ok, error} when is_error(error) -> error
      {:ok, value} -> value
      {:exit, :timeout} = error -> error
    end)
  end

  defp extract(%Stream{} = stream), do: Enum.map(stream, & &1)

  defp results_if_all(stream, fun) do
    {correct, wrong} =
      stream
      |> Stream.transform(
        :continue,
        fn
          _, {:halt, res} ->
            {:halt, res}

          elem, :continue ->
            if fun.(elem) do
              {[elem], :continue}
            else
              {[elem], {:halt, elem}}
            end
        end
      )
      |> Enum.split_with(fun)

    if Enum.empty?(wrong), do: correct, else: wrong
  end

  defp correct_result?({:error, _}), do: false
  defp correct_result?({:exit, _}), do: false
  defp correct_result?(_), do: true
end
