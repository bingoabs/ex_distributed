# ExDistributed


# Version 1
        1. When cluster init, select the first started node as leader
        2. if cluster in election, new up node will ignore update leader
            command, because the new elected leader will broadcast the 
            leader info and the need_restarted_servers to the all actived
            nodes
        3. if cluster in normal, the init status new node will ignore the
            command, the leader will update the new node
        4. if due to the net issue, there are two clusters, and each has a
            leader, that [#TODO]
        5. when follower node down, leader dispatch the servers to other nodes
        6. if leader down, into election.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_distributed` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_distributed, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/ex_distributed](https://hexdocs.pm/ex_distributed).

