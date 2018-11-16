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
  alias ExDistributed.LeaderClient
  alias ExDistributed.ServerManager

  @init_status "init"
  @election_status "election"
  @normal_status "normal"

  @doc "Available between nodes like :rpc"
  def get_current_state() do
    Logger.info("Query #{Node.self()} stat")
    LeaderStore.get()
  end

  @doc "Only leader node invoke"
  def reset(state) do
    Logger.warn("#{Node.self()} reset state: #{inspect(state)}")
    LeaderStore.set(state)
  end

  defp leader_reset_state(leader_node, nodes_name) do
    if Node.self() == leader_node do
      for node_name <- nodes_name do
        new_state = %{leader: leader_node, status: @normal_status, updated_at: Utils.current()}
        Logger.warn("#{Node.self()} send follower #{node_name} new_state: #{inspect(new_state)}")
        :rpc.call(node_name, ExDistributed.LeaderClient, :reset, [new_state])
      end
    else
      new_state = :rpc.call(leader_node, ExDistributed.LeaderClient, :get_current_state, [])
      Logger.warn("#{Node.self()} receive #{inspect(new_state)} from #{leader_node}")
      reset(new_state)
    end
  end

  defp get_actived_nodes_state(cstate) do
    NodeState.get_active_nodes()
    |> Kernel.--([Node.self()])
    |> Enum.reduce([], fn node_name, acc ->
      Logger.info("Node #{inspect(Node.self())} get active node #{inspect(node_name)} status")

      case :rpc.call(node_name, ExDistributed.LeaderClient, :get_current_state, []) do
        {:badrpc, reason} ->
          Logger.error(
            "#{inspect(Node.self())} receive rpc call #{node_name} error: #{inspect(reason)}"
          )

          NodeState.set_status(:unconnecte, node_name)
          acc

        response ->
          acc ++ [{node_name, response}]
      end
    end)
    |> Kernel.++([{Node.self(), cstate}])
  end

  defp get_max_normal_follower_leader(nodes_state) do
    Enum.reduce(nodes_state, %{}, fn {node_name, state}, acc ->
      if state.status != @init_status do
        Map.update(acc, node_name, 1, &(&1 + 1))
      else
        acc
      end
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
  def sync_leader(up_node) do
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

      state.status in [@init_status, @normal_status] ->
        leader = get_max_normal_follower_leader(nodes_state)
        Logger.info("Init status #{Node.self()} checkout leader: #{leader}")
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
  def start_global_servers([]) do
    Logger.info("Down node not services")
  end

  def start_global_servers(servers) do
    actived_nodes = NodeState.get_active_nodes()
    [left | tasks] = Enum.chunk_every(servers, length(actived_nodes))
    remote_actived_nodes = actived_nodes -- [Node.self()]

    for {node_name, servers} <- Enum.zip(remote_actived_nodes, tasks) do
      :rpc.call(node_name, ExDistributed.ServerManager, :start_servers, [servers])
    end

    ServerManager.start_servers(left)
  end
end
