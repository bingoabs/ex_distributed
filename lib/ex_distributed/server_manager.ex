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
  @doc "Reset the status by remote node"
  def reset(status) do
    Logger.info("Remote Node force reset current node #{inspect Node.self} status: #{inspect status}")
    GenServer.call(__MODULE__, {:reset, status})
  end

  def remote_start_server(names) do
    Logger.info("Node #{inspect Node.self()} receive remote start server: #{inspect names}")
    for name <- names do
      ExDistributed.Service.start_link(name)
    end
  end
  @doc "Start the server between nodes"
  def start_global_servers(names) do
    status = GenServer.call(__MODULE__, :get_status)
    actived_nodes = Enum.filter(status, fn {node_name, {node_status, _}} ->
      node_status
    end)
    [left | tasks] = Enum.chunk_every(names, actived_nodes)
    remote_actived_nodes = actived_nodes -- [Node.self()]
    # start self node servers
    remote_start_server(left)
    # start remote nodes servers
    for {node_name, servers} <- Enum.zip(remote_actived_nodes, tasks) do
      :rpc.call(node_name, ExDistributed.Connector, :remote_start_server, [servers])
    end
  end

  # callback
  def init(_) do
    {:ok, Map.new(@nodes, &({&1, []}))}
  end

  dfe handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:reset, new_status}, _from, state) do
    {:reply, new_status, new_status}
  end

end