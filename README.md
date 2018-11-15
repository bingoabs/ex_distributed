# ExDistributed


# Version 1
        1. When Node up, select the leader
        2. leader will dispatch the servers in cluster
        3. when Node down, maybe select the leader and restart the down servers
        4. when nodes not in init status, then when some nodes down, the known
        node less than half, then the node should halt self
        (this way will make reconnection easily after connection broken)
        5. node select will have a time interval, the Leader module record the Node number change, if 10s the node nnumbers not change, then start do the elections(make sure the election happen when the cluster stable)
        6. (option) when in election, new up node need to wait the election finish, and then update the leader after election
        7. (option) or maybe the new up node should into the election.

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

