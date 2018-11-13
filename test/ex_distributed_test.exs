defmodule ExDistributedTest do
  use ExUnit.Case
  doctest ExDistributed

  test "greets the world" do
    assert ExDistributed.hello() == :world
  end
end
