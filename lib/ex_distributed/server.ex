defmodule ExDistributed.Service do
  use GenServer
  require Logger

  @moduledoc """
  Record and delete the names in cluster
  """
  # Client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def add(name) do
    GenServer.call(__MODULE__, {:add, name})
  end

  def show(name) do
    GenServer.call(__MODULE__, :show)
  end

  def delete(name) do
    GenServer.cast(__MODULE__, {:pop, name})
  end

  # Server (callbacks)
  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call({:add, name}, _from, names) do
    names = names ++ [name]
    {:reply, names, name}
  end

  @impl true
  def handle_call(:show, _from, names) do
    {:reply, names, names}
  end

  @impl true
  def handle_cast({:deleten, name}, names) do
    names = names -- [name]
    {:noreply, names}
  end
end
