defmodule ExDistributed.Service do
  use GenServer
  @moduledoc """
  Global registered genserver with local registry 
  that records global genserver name
  """
  # Client
  def global_start(names) do
    # divide the server names to all nodes
    left = 
    for name <- left do
      start_link(name)
    end
  end

  def start_link(name) do
    name = {:global, name}
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def show(name) do
    GenServer.call(name, :pop)
  end

  # Server (callbacks)
  @impl true
  def init(text) do

    {:ok, text}
  end

  @impl true
  def handle_call(:show, _from, text) do
    {:reply, text, text}
  end

end