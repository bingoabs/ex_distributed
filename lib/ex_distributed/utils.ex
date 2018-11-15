defmodule ExDistributed.Utils do
  @moduledoc """
  Utils
  """
  @doc "Current utc timestamp"
  def current() do
    DateTime.utc_now() |> DateTime.to_unix()
  end
end
