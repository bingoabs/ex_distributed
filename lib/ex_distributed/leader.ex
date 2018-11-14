defmodule ExDistributed.Leader do
  @moduledoc """
  Store the leader and do the election between nodes

  All data is response by the leader
  1. if leader down, first select leader, then other nodes set status by leader instruction
  2. other node down , leader assigns the downed servers to existed nodes
  """
  use GenServer
  require Logger
  alias ExDistributed.NodeState

  @init_status "init"
  @election_status "election"
  @normal_status "normal"
  @start_election_delay 2_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end
  def start_election() do
    # make the node status update
    Process.send_after(__MODULE__, :start_election, @start_election_delay)
  end
  def get_leader() do
    {:error, :in_election}
    {:ok, leader}
  end
  # callback
  def init(_) do
    {:ok, %{is_leader: false, status: @init_status}}
  end
  def handle_info(:start_election, state) do
    # once into election status, must select a leader the 
    if state.status == @init_status do
      actived_nodes = NodeState.get_active_nodes()
      :rpc.call()
    end
    {:noreply, state}
  end

  defp delay_select_leader() do
    
  end

  defp leader_assign_servers(leader, node_name) do
    if Node.self() == leader do
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