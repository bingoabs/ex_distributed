defmodule ExDistributed.Leader do
  @moduledoc """
  Store the leader and do the election between nodes

  All data is response by the leader
  1. if leader down, first select leader, 
    then other nodes set status by leader instruction
  2. other node down , leader assigns the downed servers 
    to existed nodes
  """
  use GenServer
  require Logger
  alias ExDistributed.NodeState

  @init_status "init"
  @election_status "election"
  @normal_status "normal"
  @update_leader_delay 1_000

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
  def sync_leader(node_name) do
    # avoid to block the NodeState process
    Process.send_after(__MODULE__, {:sync_leader, node_name}, @update_leader_delay)
  end

  def get_current_state(), do: GenServer.call(:get_status)
  # callback
  def init(_) do
    {:ok,
     %{
       leader: Node.self(),
       status: @init_status,
       # main property when elections
       updated_at: Utils.current()
     }}
  end

  defp get_actived_nodes_state(cstate) do
    NodeState.get_active_nodes()
    |> Kernel.--([Node.self()])
    |> Enum.map(fn node_name ->
      node_state = :rpc.call(node_name, __MODULE__, :get_current_state, [])
      {node_name, node_state}
    end)
    |> Kernel.++([{Node.self(), cstate}])
  end

  def handle_info({:sync_leader, up_node}, state) do
    cond do
      state.status == @init_status ->
        # 1. init status two node how to set leader
        # 2. a new node join a stable cluster that already has a leader
        # 3. consider node up when election is running

        nodes_state = get_actived_nodes_state(state)

        nodes_status =
          Enum.map(nodes_state, fn {_, state} ->
            state.status
          end)

        if Enum.all?(nodes_status, &(&1 == @init_status)) do
          Logger.info("Node #{Node.self()} finds the cluster is init")
          Logger.info("Node #{Node.self()} selects first node as leader")

          {leader_node, _} =
            Enum.min_by(nodes_state, fn {node_name, state} ->
              state.updated_at
            end)

          {:noreply,
           %{
             leader: leader_node,
             status: @normal_status,
             updated_at: Utils.current()
           }}
        else
          # except cluster all init case, other situation the leader will
          # update the new up node
          {:noreply, state}
        end

      state.status == @normal_status ->
        if state.leader == Node.self() do
          # after the init status, due to the internet issue
          # the cluster divided two or more sub-cluster
          # then after issue fixed, the leaders in all cluster need 
          # do something
          nodes_state = get_actived_nodes_state(state)

          leaders_stat =
            Enum.reduce(node_state, %{}, fn {node_name, _}, acc ->
              Map.update(acc, node_name, 1, &(&1 + 1))
            end)

          # TODO: consider two cluster has same number nodes...
          {leader, _} =
            Enum.max_by(leaders_stat, fn {node_name, number} ->
              number
            end)

          if Node.self() == leader do
            # new leader update the all cluster
            # for {node_name, _} <- nodes_state do
            #   :rpc.call(node_name, __MODULE__, :reset, [Node.self()])
            # end

            # or due to the new up node will notify
            # so once update one new up node
            :rpc.call(up_node, __MODULE__, :reset, [Node.self()])
          end

          {:noreply, Map.put(state, :leader, leader)}
        else
          {:noreply, state}
        end

      # In election status, ignore the update command
      true ->
        {:noreply, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:reset, leader}, state) do
    {:noreply, %{leader: leader, status: @normal_status, updated_at: Utils.current()}}
  end
end
