defmodule ExDistributed.ServerManager do
  @moduledoc """
  Store nodes servers and
  stop and restart the servers when leader changes
  """
  require Logger
  use GenServer
  @nodes Application.get_env(:ex_distributed, :nodes)

  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_node_servers(node_name) do
    state = GenServer.call(__MODULE__, :get_status)
    Map.get(state, node_name, [])
  end

  @doc "Reset the services by leader"
  def reset(state) do
    Logger.info(
      "Leader Node force reset current node #{inspect(Node.self())} state: #{inspect(state)}"
    )

    GenServer.cast(__MODULE__, {:reset, state})
  end

  def start_servers(servers) do
    Logger.info("Node #{inspect(Node.self())} receive remote start server: #{inspect(servers)}")
    state = GenServer.call(__MODULE__, :get_status)
    state = Map.update(state, Node.self(), servers, &(&1 ++ servers))
    reset(state)
  end

  # callback
  def init(_) do
    {:ok, Map.new(@nodes, &{&1, []})}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:reset, state}, state) do
    {:noreply, state}
  end
end
