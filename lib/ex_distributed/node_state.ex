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
        old_status = Map.get(acc, node_name)
        case Node.ping(node_name) do
          :pang ->
            if old_status == true do
              emit_node_down(node_name)
            end
            Map.put(acc, node_name, false)
          :pong ->
            if old_status == false do
              emit_node_up(node_name)
            end
            Map.put(acc, node_name, true)
        end
      end)

    refresh_nodes()
    {:noreply, state}
  end

  @doc "Select new leader and refresh the nodes status"
  def emit_node_up(node_name) do
    Logger.info("Node #{inspect(Node.self())} receive #{inspect(node_name)} up")
    LeaderClient.sync_leader(node_name)
  end

  @doc "Restart server when nodedown and check the leader status"
  def emit_node_down(down_node) do
    Logger.warn("Node #{inspect(Node.self())} receive #{inspect(down_node)} down")
    LeaderClient.check_leader_and_restart_services(down_node)
  end
  @doc "Only the leader emit the contious refresh, like heart beat"
  def refresh_nodes() do
    Logger.info("#{inspect(Node.self())} will refresh nodes again")
    Process.send_after(self(), :refresh_nodes, @refresh)
  end
end
