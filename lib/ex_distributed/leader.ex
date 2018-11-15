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
  @update_leader_delay 2_000

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def reset(leader) do
    GenServer.cast({:reset, leader})
  end

  @doc """
  if in election status, then ignore the command;
  if init/normal status, then query other nodes status:
    exist election status -> then wait until election finish, then update leader
    all init or normal status -> start a election
  """
  def update_leader() do
    Process.send_after(__MODULE__, :update_leader, @update_leader_delay)
  end

  def get_current_state(), do: GenServer.call(:get_status)
  # callback
  def init(_) do
    {:ok,
     %{
       leader: Node.self(),
       status: @init_status,
       start_at: ExDistributed.Utils
     }}
  end

  def handle_info(:update_leader, state) do
    # if in election status, ignore the update command
    if state.status in [@init_status, @normal_status] do
      actived_nodes = NodeState.get_active_nodes()
      other_nodes = actived_nodes -- [Node.self()]
      # query all actived nodes, then compare the leader data
      # update the main leader as current node leader
      responses =
        Enum.map(other_nodes, fn node_name ->
          node_state = :rpc.call(node_name, __MODULE__, :get_current_state, [])
          {node_name, node_state}
        end)

      responses = responses ++ [{Node.self(), state}]
      # if exist election status, then 
    end

    {:noreply, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:reset, leader}, state) do
    {:noreply, %{leader: leader, status: @normal_status}}
  end

  # TODO
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
