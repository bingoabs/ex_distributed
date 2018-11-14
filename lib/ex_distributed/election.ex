defmodule ExDistributed.Election do
  @moduledoc """
  1. refresh the nodes status
  2. monitor the nodes down and up
  3. do selection between nodes in the cluster
  %{node => %{is_leader: true/false, connected_status: true/false}}

  All data is response by the leader
  1. if one node down or up, consider to refresh leader
  2. leader should assign the servers between nodes
  """
  use GenServer
  require Logger
  @nodes Application.get_env(:ex_distributed, :nodes)
  @refresh_nodes 10_000
  @election_delay 2_000
  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def get_active_nodes() do
    
  end
  defp select_leader() do
    #TODO
  end

  #callback
  def init(_) do
    default = %{is_leader: false, connected_status: false}
    refresh_nodes()
    monitor_nodes()
    {:ok, Map.new(@nodes, &({&1, default}))}
  end
  @doc "Ping the unconnected nodes"
  def handle_info(:refresh_nodes, state) do
    unconnected_nodes = Enum.filter(state, &(&1.connected_status == false))
    Logger.info("Node #{inspect Node.self} refresh nodes: #{inspect unconnected_nodes}")
    responses = Enum.map(unconnected_nodes, &(Node.ping(&1)))
    if :pang in responses do
      refresh_nodes()
    end
    {:noreply, state}
  end
  @doc "Select new leader and refresh the nodes status"
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("Node #{inspect Node.self()} connect #{inspect node_name}")
    Logger.info("Node #{inspect Node.self()} delay select the leader")
    # avoid to block the many nodes up
    delay_select_leader()
    node_state = Map.get(state, node_name)
    updated_node_state = Map.put(node_state, :connected_status, true)
    state = Map.put(state, node_name, updated_node_state)
    {:noreply, state}
  end
  @doc "Restart server when nodedown and check the leader status"
  def handle_info({:nodedown, node_name}, state) do
    Logger.warning("Node #{inspect node_name} down")
    Logger.warning("Redispatch the servers to other nodes")
    {_, need_restart_servers} = Map.get(state, node_name)
    restart_downnode_servers(need_restart_servers)
    {:noreply, Map.put(state, node_name, {false, []})}
  end
  @doc "Select a worker to do the election"
  def handle_info(:select_leader, state) do
    "TODO"
  end
  defp refresh_nodes() do
    Process.send_after(self, :refresh_nodes, @refresh_nodes)
  end
  @doc "Make current process listen the node up and down"
  defp monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end
  defp delay_select_leader() do
    Process.send_after(self, :select_leader, @election_delay)
  end

  defp restart_downnode_servers(servers) do
    core_node = select_leader_node()
    if core_node == Node.self() do
      Logger.info("Current Node #{inspect core_node} selected")
      Logger.info("start downnode servers: #{inspect servers}")
      start_global_servers(servers)
    end
  end

  defp update_new_node_state(new_node, state) do
    core_node = select_leader_node()
    if Node.self() === core_node do
      Logger.info("Current Node #{inspect core_node} selected")
      Logger.info("start replace new node status")
      # TODO: if error
      :rpc.call(new_node, ExDistributed.Connector, :reset_status, [state])
    end
  end

end