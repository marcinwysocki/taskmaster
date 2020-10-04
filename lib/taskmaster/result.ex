defmodule Taskmaster.Result do
  @enforce_keys [:action, :result]
  defstruct [:action, :result]
end
