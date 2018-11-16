defmodule ExDistributed.NodeState do
  @moduledoc """
  1. refresh the nodes status
  2. monitor the nodes down and up
  3. do selection between nodes in the cluster
  """
  use GenServer
  require Logger
  alias ExDistributed.LeaderClient
  # alias ExDistributed.ServerManager
  @nodes Application.get_env(:ex_distributed, :nodes)
  @refresh 1_000
  @max_refresh 60_000
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

  def get_nodes_name(state) do
    Enum.map(state, fn {node_name, _} -> node_name end)
  end

  def set_status(:unconnecte, node_name) do
    Logger.info("Node #{Node.self()} set #{inspect(node_name)} unconnected")
    GenServer.cast(__MODULE__, {:unconnecte, node_name})
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

  def handle_cast({:unconnecte, node_name}, state) do
    {:noreply, Map.put(state, node_name, false)}
  end

  @doc "Ping the unconnected nodes"
  def handle_info({:refresh_nodes, timeout}, state) do
    Logger.info("#{inspect(Node.self())} state: #{inspect(state)}")
    nodes_name = get_nodes_name(state)
    Logger.info("Node #{inspect(Node.self())} refresh nodes: #{inspect(nodes_name)}")

    state =
      Enum.reduce(nodes_name, state, fn node_name, acc ->
        case Node.ping(node_name) do
          :pang -> Map.put(acc, node_name, false)
          :pong -> Map.put(acc, node_name, true)
        end
      end)

    if Enum.all?(state, fn {_, status} -> status end) do
      timeout = timeout * 2

      if timeout > @max_refresh do
        refresh_nodes(@max_refresh)
      else
        refresh_nodes(timeout)
      end
    else
      refresh_nodes()
    end

    {:noreply, state}
  end

  @doc "Select new leader and refresh the nodes status"
  def handle_info({:nodeup, node_up}, state) do
    Logger.info("Node #{inspect(Node.self())} receive #{inspect(node_up)} up")
    # avoid to block the downnode status update
    Task.start(LeaderClient, :sync_leader, [node_up])
    {:noreply, Map.put(state, node_up, true)}
  end

  @doc "Restart server when nodedown and check the leader status"
  def handle_info({:nodedown, down_node}, state) do
    Logger.warn("Node #{inspect(Node.self())} receive #{inspect(down_node)} down")
    # avoid to block the NodeState process
    Task.start(LeaderClient, :down_node, [down_node])
    {:noreply, Map.put(state, down_node, false)}
  end

  defp refresh_nodes(timeout \\ @refresh) do
    Logger.info("#{inspect(Node.self())} will refresh nodes again")
    Process.send_after(self(), {:refresh_nodes, timeout}, timeout)
  end

  @doc "Current process listen the node up and down"
  def monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end
end
