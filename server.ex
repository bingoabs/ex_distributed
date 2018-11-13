defmodule ExDistributed.server do
  @moduledoc """
  Test GenServer {:global, term} property
  """
  use GenServer

  def start_link(value, name) do
    GenServer.start_link(__MODULE__, [value], name: name)
  end

  def show(pid) do
    GenServer.call(pid, :show)
  end

  @impl true
  def init(value) do
    {:ok, value}
  end

  def handle_call(:show, _from, value) do
    {:reply, value, value}
  end
end


