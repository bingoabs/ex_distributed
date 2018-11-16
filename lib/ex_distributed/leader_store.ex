defmodule ExDistributed.LeaderStore do
  @moduledoc """
  Store the leader info, avoid to block 
  the `leader status` query between nodes
  """
  use GenServer
  alias ExDistributed.Utils
  require Logger
  @init_status "init"

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Only used in same node"
  def set(state) do
    Logger.warn("#{Node.self()} set leader_store state: #{inspect(state)}")
    GenServer.cast(__MODULE__, {:set, state})
  end

  @doc "Available between nodes like :rpc"
  def get() do
    Logger.info("#{Node.self()} get leader_sotre state")
    GenServer.call(__MODULE__, :get)
  end

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

  def handle_cast({:set, new_state}, _old_state) do
    {:noreply, new_state}
  end

  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end
end
