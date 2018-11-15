defmodule ExDistributed.Service do
  use GenServer
  require Logger

  @moduledoc """
  Register and start servers in cluster
  """
  # Client
  def start(name) do
    Logger.info("Node #{inspect(Node.self())} start server #{inspect(name)}")
    start_link(name)
  end

  def show(name) do
    GenServer.call(name, :show)
  end

  def shutdown(name) do
    GenServer.stop(name, :shutdown)
  end

  def start_link(name) do
    GenServer.start_link(__MODULE__, %{}, name: {:global, name})
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

  @impl true
  def terminate(:shutdown, state) do
    Logger.info("Node #{inspect(Node.self())} stop server #{inspect(name)}")
  end
end
