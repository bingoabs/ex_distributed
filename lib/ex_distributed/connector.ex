defmodule ExDistributed.Connector do
  @moduledoc """
  Used to connect between nodes.
  Like distrubute the tasks
  and start services when some node down
  """
  require Logger
  use GenServer
  @nodes Application.get_env(:ex_distributed, :nodes)
  @refresh_nodes 10_000

  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  @doc "Reset the status by remote node"
  def reset_status(status) do
    Logger.info("Remote Node force reset current node status: #{inspect status}")
    GenServer.call(__MODULE__, {:reset, status})
  end
  @doc "Start the server between nodes"
  def start_global_servers(names) do
    status = GenServer.call(__MODULE__, :get_status)
    actived_nodes = Enum.filter(status, fn {node_name, {node_status, _}} ->
      node_status
    end)
    tasks = Enum.chunk_every(names, actived_nodes)
    # start self part
    # delte self part
    # send to other nodes
  end

  defp restart_downnode_servers(servers) do
    core_node = select_core_node(node_name)
    if core_node == Node.self() do
      Logger.info("Current Node #{inspect core_node} selected")
      Logger.info("start downnode servers: #{inspect servers}")
      start_global_servers(servers)
    end
  end

  defp update_new_node_state(new_node, state) do
    core_node = select_core_node(node_name)
    if Node.self() === core_node do
      Logger.info("Current Node #{inspect core_node} selected")
      Logger.info("start replace new node status")
      # TODO: if error
      :rpc.call(new_node, ExDistributed.Connector, :reset_status, [state])
    end
  end
  # callback
  def init(_) do
    # init status with unconnect-status without service names
    state = 
      Enum.reduce(@nodes, %{}, fn node_name, acc ->
        # {connection status, server names}
        Map.put(acc, node_name, {false, []})
      end)
    # all nodes can not start at same time
    refresh_nodes()
    monitor_nodes()
    {:ok, state}
  end

  dfe handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:reset, new_status}, _from, state) do
    {:reply, new_status, new_status}
  end

  @doc "Only ping the other nodes"
  def handle_info(:refresh_nodes, state) do
    unconnected_nodes = Enum.filter(state, &(&1.status == false))
    Logger.info("refresh_nodes for nodes: #{inspect unconnected_nodes}")
    for node_name <- unconnected_nodes do
      Node.ping(node_name)
    end
    refresh_nodes()
    {:noreply, state}
  end
  @doc "Change new connected node status"
  def handle_info({:nodeup, node_name}, state) do
    Logger.info("New Connected Node: #{inspect node_name}")
    Logger.info("Send message to New Node, clear outdate servers")
    update_new_node_state(node_name, state)
    {:noreply, state}
  end
  def handle_info({:nodedown, node_name}, state) do
    Logger.warning("Node #{inspect node_name} down")
    Logger.warning("Redispatch the servers to other nodes")
    {_, need_restart_servers} = Map.get(state, node_name)
    restart_downnode_servers(need_restart_servers)
    {:noreply, Map.put(state, node_name, {false, []})}
  end

  defp refresh_nodes() do
    Process.send_after(self, :refresh_nodes, @refresh_nodes)
  end

  defp monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end

end