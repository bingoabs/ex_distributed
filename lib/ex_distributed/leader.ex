defmodule ExDistributed.Leader do
  @moduledoc """
  Store the leader and do the election between nodes

  All data is response by the leader
  1. if leader down, first select leader, then other nodes set status by leader instruction
  2. other node down , leader assigns the downed servers to existed nodes
  """
  use GenServer
  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def start_election() do
    todo
  end
  def get_leader() do
    todo
  end
  defp delay_select_leader() do
    Process.send_after(self, :select_leader)
  end

  defp leader_assign_servers(leader, node_name) do
    if Node.self() == leader do
      # get down node services
      # assign to nodes
      :rpc.call(new_node, ExDistributed.Connector, :reset_status, [state])
    end
  end
  def get_leader_node(state) do
    leader =
      Enum.find(state, nil, fn {node_name, value} ->
        value.is_leader == true
      end)
    case leader do
      nil -> nil
      {node_name, _} -> node_name
    end
  end
end