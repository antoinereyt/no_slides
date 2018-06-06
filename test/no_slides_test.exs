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

    #IO.puts "\nGive ring distribution a chance. Be patient..."
    #Process.sleep(60000) # Crazy way to give the ring chance for some distribution. Takes a minute or so!

    #IO.inspect NoSlides.Service.ring_status() # local, meaningless. Fails without RiakCore running, e.g. 'mix test --no-start'
    IO.inspect RiakCluster.ring_status(hd(nodeNames)) # remote call

    on_exit fn ->
      IO.puts "\nThe test is done! Shutting down..."
      IO.inspect RiakCluster.ring_status(hd(nodeNames))
      # TODO: stop the slaves
    end
    [nodes: nodeNames]
  end


  test "ping different nodes in a RiakCore cluster", context do
    nodeNames = context.nodes
    :pong = rc_command(hd(nodeNames), :ping)

    for _n <- 1..100 do
      :pong = rc_command(pick_random(nodeNames), :ping, [:rand.uniform(100_000_000)])
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

    # test updating value
    :ok = rc_command(first_node, :put, [:k1, :v_new])
    :v_new = rc_command(first_node, :get, [:k1])
  end

  test "coverage with key-value pairs in a RiakCore cluster", context do
    nodeNames = context.nodes
    first_node = hd(nodeNames)

    # delete all keys to start with a know state
    [] = rc_command(first_node, :clear, [])
    [] = rc_command(first_node, :keys, [])
    [] = rc_command(first_node, :values, [])

    k_v_pairs = Enum.map(1..100, &({"k#{:rand.uniform(100_000)}", "v#{&1}"}))

    Enum.each(k_v_pairs, fn({k, v}) -> rc_command(pick_random(nodeNames), :put, [k, v]) end)

    actual_keys = rc_command(first_node, :keys, [])
    actual_values = rc_command(first_node, :values, [])

    assert 100 == length(actual_keys)
    assert 100 == length(actual_values)
    assert have_same_elements(actual_keys, Enum.map(k_v_pairs, fn({k, _v}) -> k end))
    assert have_same_elements(actual_values, Enum.map(k_v_pairs, fn({_k, v}) -> v end))

    # store should be empty after a new clear
    [] = rc_command(first_node, :clear, [])
    [] = rc_command(first_node, :keys, [])
    [] = rc_command(first_node, :values, [])
  end

  defp pick_random(nodes) do
    i = :rand.uniform(length(nodes)) - 1 # index of node to use
    Enum.at(nodes, i)
  end

  defp rc_command(node, command) do rc_command(node, command, []) end

  defp rc_command(node, command, args) do
    :rpc.call(String.to_atom(node), NoSlides.Service, command, args)
  end

  defp have_same_elements(list1, list2) do
    list1 -- list2 == [] and list2 -- list1 == []
  end
end
