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

  # callback
  def init(_) do
    # init status with unconnect-status without service names
    state = 
      Enum.reduce(@nodes, %{}, fn node, acc ->
        Map.put(acc, node, %{status: false, server_names: []})
      end)
    # all nodes can not start at same time
    refresh_nodes()
    monitor_nodes()
    {:ok, state}
  end

  def handle_info(:refresh_nodes_status, state) do
    unconnected_nodes = Enum.filter(state, &(&1.status == false))
    Logger.info("refresh_nodes for nodes: #{inspect unconnected_nodes}")
    state =
      Enum.reduce(unconnected_nodes, state, fn {node, value}, state ->
        case Node.ping(node) do
          :pang -> state
          :pong -> Map.put(state, node, Map.put(value, :status, true))
        end
      end)
    refresh_nodes()
    {:ok, state}
  end

  {:nodedown, :node3@bingo}
  {:nodeup, :node3@bingo}

  defp refresh_nodes() do
    Process.send_after(self, :refresh_nodes_status, @refresh_nodes)
  end

  defp monitor_nodes() do
    :net_kernel.monitor_nodes(true)
  end

end