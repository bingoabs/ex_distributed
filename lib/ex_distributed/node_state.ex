defmodule ExDistributed.NodeState do
  @moduledoc """
  1. refresh the nodes status
  2. monitor the nodes down and up
  3. do selection between nodes in the cluster
  """
  use GenServer
  require Logger
  alias ExDistributed.Leader
  # alias ExDistributed.ServerManager
  @nodes Application.get_env(:ex_distributed, :nodes)
  @refresh 1_000
  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_active_nodes() do
    GenServer.call(__MODULE__, :get_status)
    |> Enum.filter(fn {_, node_status} ->
      node_status
    end)
    |> Enum.map(fn {node_name, _} -> node_name end)
  end

  def get_unactive_nodes(state) do
    Enum.filter(state, fn {_, node_status} ->
      node_status == false
    end)
    |> Enum.map(fn {node_name, _} -> node_name end)
  end

  # callback
  def init(_) do
    refresh_nodes()
    monitor_nodes()
    state = Map.new(@nodes, &{&1, false})
    {:ok, Map.put(state, Node.self(), true)}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @doc "Ping the unconnected nodes"
  def handle_info(:refresh_nodes, state) do
    unconnected_nodes = get_unactive_nodes(state)
    Logger.info("Node #{inspect(Node.self())} refresh nodes: #{inspect(unconnected_nodes)}")

    {responses, state} =
      Enum.map_reduce(unconnected_nodes, state, fn node_name, acc ->
        case Node.ping(node_name) do
          :pang -> {:pang, acc}
          :pong -> {:pong, Map.put(acc, node_name, true)}
        end
      end)

    if :pang in responses do
      refresh_nodes()
    end

    {:noreply, state}
  end

  @doc "Select new leader and refresh the nodes status"
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Node #{inspect(Node.self())} receive #{inspect(node_name)} up")
    Leader.sync_leader(node_name)
    {:noreply, Map.put(state, node_name, true)}
  end

  @doc "Restart server when nodedown and check the leader status"
  def handle_info({:nodedown, down_node}, state) do
    Logger.warn("Node #{inspect(Node.self())} receive #{inspect(down_node)} down")
    Leader.check_leader_and_restart_services(down_node)
    {:noreply, Map.put(state, down_node, false)}
  end

  defp refresh_nodes() do
    Process.send_after(self(), :refresh_nodes, @refresh)
  end

  @doc "Current process listen the node up and down"
  def monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end
end
