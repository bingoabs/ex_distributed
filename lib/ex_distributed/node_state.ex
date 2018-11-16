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
  def handle_info(:refresh_nodes, state) do
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

    refresh_nodes()
    {:noreply, state}
  end

  @doc "Select new leader and refresh the nodes status"
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Node #{inspect(Node.self())} receive #{inspect(node_name)} up")
    LeaderClient.sync_leader(node_name)
    {:noreply, Map.put(state, node_name, true)}
  end

  @doc "Restart server when nodedown and check the leader status"
  def handle_info({:nodedown, down_node}, state) do
    Logger.warn("Node #{inspect(Node.self())} receive #{inspect(down_node)} down")
    LeaderClient.check_leader_and_restart_services(down_node)
    {:noreply, Map.put(state, down_node, false)}
  end

  def handle_info(any, state) do
    Logger.error("donot know why this show: #{inspect(any)}")
    Logger.error("#inspect(state)")
    {:noreply, state}
  end

  defp refresh_nodes() do
    Logger.info("#{inspect(Node.self())} will refresh nodes again")
    Process.send_after(self(), :refresh_nodes, @refresh)
  end

  @doc "Current process listen the node up and down"
  def monitor_nodes() do
    for node_name <- @nodes do
      Node.monitor(node_name, true)
    end

    # :net_kernel.monitor_nodes(true)
  end
end
