defmodule ExDistributed.ServerManager do
  @moduledoc """
  Store nodes servers and
  stop and restart the servers when leader changes
  """
  require Logger
  use GenServer
  alias ExDistributed.Leader
  alias ExDistributed.NodeState
  @nodes Application.get_env(:ex_distributed, :nodes)
  @max_retry 2
  @down_delay 5_000
  # client
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def restart_downnode_services(down_node, retry \\ 0) do
    Process.send_after(__MODULE__, {:restart_services, down_node, retry}, @down_delay)
  end
  @doc "Reset the status by remote node"
  def reset(status) do
    Logger.info("Remote Node force reset current node #{inspect Node.self} status: #{inspect status}")
    GenServer.call(__MODULE__, {:reset, status})
  end
  def remote_start_server(servers) do
    Logger.info("Node #{inspect Node.self()} receive remote start server: #{inspect servers}")
    GenServer.cast({:start_server, servers})
  end
  @doc "Start the server between nodes"
  def start_global_servers(servers) do
    active_nodes = NodeState.get_active_nodes()
    [left | tasks] = Enum.chunk_every(servers, actived_nodes)
    remote_actived_nodes = actived_nodes -- [Node.self()]
    # start self node servers
    # start remote nodes servers
    for {node_name, servers} <- Enum.zip(remote_actived_nodes, tasks) do
      :rpc.call(node_name, ExDistributed.ServerManager, :remote_start_server, [servers])
    end
    Enum.reduce(left, [], fn server, acc ->
      case ExDistributed.Service.start_link(server) do
        {:ok, _} -> acc ++ [server]
        _other -> acc
      end
    end)
  end
  # callback
  def init(_) do
    {:ok, Map.new(@nodes, &({&1, []}))}
  end
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end
  def handle_call({:reset, new_status}, _from, state) do
    {:reply, new_status, new_status}
  end
  def handle_cast({:start_server, servers}, state) do
    success_servers =
      Enum.reduce(servers, [], fn server, acc ->
        case ExDistributed.Service.start_link(server) do
          {:ok, _} -> acc ++ [server]
          _other -> acc
        end
      end)
    servers = Map.get(state, Node.self()) ++ success_servers
    {:noreply, Map.put(state, Node.self(), servers)}
  end
  def handle_info({:restart_services, down_node, retry}, state) do
    case Leader.get_leader() do
      {:error, :in_election} -> restart_downnode_services(down_node, retry + 1)
      {:ok, leader} ->
        if leader == Node.self() do
          active_nodes = NodeState.get_active_nodes()
          cond do
            (down_node in active_nodes) and retry <= @max_retry ->
              Logger.info("Node #{inspect Node.self} stop restart #{inspect down_node} services")
              {:noreply, state}
            true ->
              success_servers = start_global_servers(Map.get(state, down_node))
              servers = Map.get(state, Node.self())
              {:noreply, state}
          end
        end
    end
  end

end