defmodule NoSlidesTest do
  use ExUnit.Case
  alias NoSlides.RiakCluster

  doctest NoSlides

  # "setup_all" is called once per module before any test runs
  setup_all do
    # start the RiakCore cluster
    assert !Node.alive?()
    nodeNames = RiakCluster.start_test_nodes()
    assert Node.alive?()
    IO.inspect Node.list

    #IO.inspect NoSlides.Service.ring_status() # local, meaningless. Fails without RiakCore running, e.g. 'mix test --no-start'
    IO.inspect RiakCluster.ring_status(hd(nodeNames)) # remote call
    [nodes: nodeNames]
  end


  test "ping different nodes in a RiakCore cluster", context do
    nodeNames = context.nodes
    :pong = rc_command(hd(nodeNames), :ping)

    for _n <- 1..100 do
      i = :rand.uniform(length(nodeNames)) - 1 # index of node to use
      :pong = rc_command(Enum.at(nodeNames, i), :ping, [:rand.uniform(100_000_000)])
    end
  end

  test "try key-value pairs in a RiakCore cluster", context do
    nodeNames = context.nodes
    first_node = hd(nodeNames)

    
    :ok = rc_command(first_node, :put, [:k1, :v1])
    :ok = rc_command(first_node, :put, [:k2, :v2])
    :ok = rc_command(first_node, :put, [:k3, :v3])

    # get from any of the nodes
    for node <- nodeNames do
      :v1 = rc_command(node, :get, [:k1])
      :v2 = rc_command(node, :get, [:k2])
      :v3 = rc_command(node, :get, [:k3])
      nil = rc_command(node, :get, [:k10])
    end
  end

  defp rc_command(node, command) do rc_command(node, command, []) end

  defp rc_command(node, command, args) do
    :rpc.call(String.to_atom(node), NoSlides.Service, command, args)
  end

end
