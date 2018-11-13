defmodule ExDistributed do
  @moduledoc """
  Init the servers
  """

  def start_servers(names) do
    ExDistributed.Service.global_start(names)
  end
end
