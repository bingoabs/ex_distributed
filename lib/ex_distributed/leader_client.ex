defmodule ExDistributed.LeaderClient do
  @moduledoc """
  Store the leader and do the election between nodes

  All data is response by the leader
  1. if leader down, first select leader, 
    then other nodes set status by leader instruction
  2. other node down , leader assigns the downed servers 
    to existed nodes
  """
  require Logger
  alias ExDistributed.Utils
  alias ExDistributed.NodeState
  alias ExDistributed.LeaderStore
  alias ExDistributed.ServerManager

  @init_status "init"
  @election_status "election"
  @normal_status "normal"

  @doc "Available between nodes like :rpc"
  def get_current_state(), do: LeaderStore.get()
  @doc "Only leader node invoke"
  def reset(state), do: LeaderStore.set(state)

  defp leader_reset_state(leader_node, nodes_name) do
    if Node.self() == leader_node do
      for node_name <- nodes_name do
        new_state = %{leader: leader_node, status: @normal_status, updated_at: Utils.current()}

        if node_name == Node.self() do
          reset(new_state)
        else
          :rpc.call(node_name, __MODULE__, :reset, [new_state])
        end
      end
    end
  end

  @doc """
  if in election status, then ignore the command;
  if init/normal status, then query other nodes status:
    exist election status -> then wait until election finish, then update leader
    all init or normal status -> start a election
  """
  def sync_leader(up_node) do
    # avoid to block the NodeState process
    Task.Supervisor.async(ExDistributed.TaskSupervisor, &__MODULE__.private_sync_leader/1, [
      up_node
    ])
  end

  @doc """
  To follower downnode, leader will do somethin
  if leader download, then into election
  after election, leader will update node servers in cluster
  """
  def check_leader_and_restart_services(down_node) do
    # avoid to block the downnode status update
    Task.Supervisor.async(ExDistributed.TaskSupervisor, &__MODULE__.down_node/1, [down_node])
  end

  defp get_actived_nodes_state(cstate) do
    NodeState.get_active_nodes()
    |> Kernel.--([Node.self()])
    |> Enum.map(fn node_name ->
      Logger.error("do rpc: #{inspect(node_name)}")
      node_state = :rpc.call(node_name, __MODULE__, :get_current_state, [])
      {node_name, node_state}
    end)
    |> Kernel.++([{Node.self(), cstate}])
  end

  defp get_max_follower_leader(nodes_state) do
    Enum.reduce(nodes_state, %{}, fn {node_name, _}, acc ->
      Map.update(acc, node_name, 1, &(&1 + 1))
    end)
    |> Enum.max_by(fn {_node_name, number} ->
      number
    end)
    |> elem(0)
  end

  @doc """
  In cluster init status, select the first started node as leader
  If a init node join the stable cluster, the leader will set the state
  If a init node join the cluster that in election, stop and wait the 
    election stop new leader will set the nodes state after election
  If a normal status node join cluster(due to the internet issue 
    the cluster divides two or more sub-clusters then after issue fixed)
    Now exists more than one leader, so each leader will count the follower
    number, the max follower one wins(It will work fine, if less half of nodes down)
    Current version ignore the election situation.
    <!-- TODO: If cluster in election, wait new leader set the state
    other situations just find the main leader and the main leader 
    set the cluster status -->
  """
  def private_sync_leader(up_node) do
    state = get_current_state()
    nodes_state = get_actived_nodes_state(state)

    nodes_status =
      Enum.map(nodes_state, fn {_, state} ->
        state.status
      end)

    cluster_in_init = Enum.all?(nodes_status, &(&1 == @init_status))

    cond do
      state.status == @init_status and cluster_in_init ->
        Logger.info("Node #{Node.self()} finds the cluster is init")
        Logger.info("Node #{Node.self()} selects first node as leader")

        {leader_node, _} =
          Enum.min_by(nodes_state, fn {_node_name, state} ->
            state.updated_at
          end)

        nodes = Enum.map(nodes_state, &elem(&1, 0))
        leader_reset_state(leader_node, nodes)

      state.status == @normal_status ->
        leader = get_max_follower_leader(nodes_state)
        leader_reset_state(leader, [up_node])

      true ->
        :ok
    end
  end

  def down_node(down_node) do
    state = get_current_state()
    nodes_state = get_actived_nodes_state(state)

    nodes_status =
      Enum.map(nodes_state, fn {_, state} ->
        state.status
      end)

    cond do
      @election_status in nodes_status ->
        Logger.info("Cluster election, #{inspect(Node.self())} do nothing")

      state.leader != Node.self() ->
        Logger.info("#{inspect(Node.self())} is not leader, pass")

      state.leader == down_node ->
        Logger.warn("Cluster leader #{inspect(down_node)} down, start election")

      # TODO: do elections

      state.leader == Node.self() ->
        Logger.info("Leader #{inspect(Node.self())} receive #{inspect(down_node)} down")
        Logger.info("Leader restart the services")
        services = ServerManager.get_node_servers(down_node)
        start_global_servers(services)
    end
  end

  @doc "Start the server between nodes"
  def start_global_servers(servers) do
    actived_nodes = NodeState.get_active_nodes()
    [left | tasks] = Enum.chunk_every(servers, actived_nodes)
    remote_actived_nodes = actived_nodes -- [Node.self()]

    for {node_name, servers} <- Enum.zip(remote_actived_nodes, tasks) do
      :rpc.call(node_name, ServerManager, :start_servers, [servers])
    end

    ServerManager.start_servers(left)
  end
end
