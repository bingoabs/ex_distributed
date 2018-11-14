defmodule ExDistributed.NodeState do
  @moduledoc """
  1. refresh the nodes status
  2. monitor the nodes down and up
  3. do selection between nodes in the cluster
  """
  use GenServer
  require Logger
  alias ExDistributed.Leader
  alias ExDistributed.ServerManager
  @nodes Application.get_env(:ex_distributed, :nodes)
  @refresh 10_000
  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def get_active_nodes(state) do
    active_nodes = Enum.filter(state, fn {node_name, node_state} ->
      node_state
    end)
    Enum.map(active_nodes, fn {node_name, _} -> node_name end)
  end
  def get_unactive_nodes(state) do
    unactive_nodes = Enum.filter(state, fn {node_name, node_state} ->
      node_state = false
    end)
    Enum.map(active_nodes, fn {node_name, _} -> node_name end)
  end
  #callback
  def init(_) do
    refresh_nodes()
    monitor_nodes()
    state = Map.new(@nodes, &({&1, false}))
    {:ok, Map.put(state, Node.self(), true)}
  end
  def handle_call(:get_status, state) do
    {:reply, state, state}
  end
  @doc "Ping the unconnected nodes"
  def handle_info(:refresh_nodes, state) do
    unconnected_nodes = get_unactive_nodes(state)
    Logger.info("Node #{inspect Node.self} refresh nodes: #{inspect unconnected_nodes}")
    {responses, state} =
      Enum.map_reduce(unconnected_nodes, state, fn node_name, acc ->
        response = Node.ping(node_name)
        if responses == :pang do
          {response, acc}
        else
          {response, Map.put(acc, node_name, true)}
        end
      end)
    if :pang in responses do
      refresh_nodes()
    end
    {:noreply, state}
  end
  @doc "Select new leader and refresh the nodes status"
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Node #{inspect Node.self()} connect #{inspect node_name}")
    Leader.start_election()
    {:noreply, Map.put(state, node_name, true)}
  end
  @doc "Restart server when nodedown and check the leader status"
  def handle_info({:nodedown, node_name}, state) do
    Logger.warning("Node #{inspect Node.self} receive #{inspect node_name} down")
    ServerManager.restart_downnode_services(node_name)
    {:noreply, Map.put(state, node_name, false)}
  end
  defp refresh_nodes() do
    Process.send_after(self, :refresh_nodes, @refresh)
  end
  @doc "Current process listen the node up and down"
  defp monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end
end