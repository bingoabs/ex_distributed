defmodule ExDistributed.LeaderStore do
  @moduledoc """
  Store the leader info, avoid to block 
  the `leader status` query between nodes
  """
  use GenServer
  require Logger
  alias ExDistributed.Utils
  @init_status "init"

  # [:leader, :status, :updated_at, :voted, :ticket]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Available between nodes like :rpc"
  def get() do
    Logger.info("#{Node.self()} get leader_sotre state")
    GenServer.call(__MODULE__, :get)
  end

  def into_election(election_status) do
    GenServer.call(__MODULE__, {:into_election, election_status})
  end

  @doc "Only used in same node"
  def set(state) do
    Logger.warn("#{Node.self()} set leader_store state: #{inspect(state)}")
    GenServer.cast(__MODULE__, {:set, state})
  end

  # callback
  def init(_) do
    {:ok,
     %{
       leader: Node.self(),
       status: @init_status,
       updated_at: Utils.current(),
       voted: false,
       ticket: 0
     }}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:into_election, new_state}, _from, state) do
    {success, state} =
      case state do
        %{voted: false} -> {true, new_state}
        %{voted: true} -> {false, state}
      end

    {:reply, success, state}
  end

  def handle_cast({:set, new_state}, _old_state) do
    {:noreply, new_state}
  end
end
