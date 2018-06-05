defmodule NoSlides.RiakCluster do
  @moduledoc false
  ## derived from Phoenix.PubSub.Cluster and Riak_core example at https://github.com/lambdaclass/riak_core_tutorial

  def start_test_nodes() do
    #assert !Node.alive?()
    start_master()
    #assert Node.alive?()

    nodes = Application.get_env(:no_slides, :nodes, [])
    # start nodes serially:
    #for {node, web_port, handoff_port} <- nodes, do: start_node(node, web_port, handoff_port)
    # or start all nodes in parallel:
    nodes
    |> Enum.map(&Task.async(fn  -> {node, web_port, handoff_port} = &1; start_node(node, web_port, handoff_port) end))
    |> Enum.map(&Task.await(&1, 30_000))

    nodeNames = Enum.map(nodes, &(elem(&1, 0)))
    build_cluster(nodeNames)
    nodeNames
  end

  def ring_status(node) do
    #rpc(String.to_atom(node), :riak_core_console, :member_status, [[]])
    rpc(String.to_atom(node), NoSlides.Service, :ring_status, [])
  end

  defp start_master() do
    :ok = :net_kernel.monitor_nodes(true)
    _ = :os.cmd('epmd -daemon')

    # Turn node into a distributed node with the given long name
    :net_kernel.start([:"primary@127.0.0.1"])

    # Allow spawned nodes to fetch all code from this node
    :erl_boot_server.start([])
    allow_boot '127.0.0.1'
  end

  defp start_node(node_host, web_port, handoff_port) do
    {:ok, node} = :slave.start('127.0.0.1', node_name(node_host), inet_loader_args())
    data_dir = './data/#{node_host}' # single quotes for compatibility with Erlang

    add_code_paths(node)
    rpc(node, Application, :load, [:lager])
    rpc(node, Application, :load, [:riak_core])
    rpc(node, Application, :put_env, [:riak_core, :ring_state_dir, data_dir])
    rpc(node, Application, :put_env, [:riak_core, :platform_data_dir, data_dir])

    rpc(node, Application, :put_env, [:riak_core, :web_port, web_port])
    rpc(node, Application, :put_env, [:riak_core, :handoff_port, handoff_port])
    rpc(node, Application, :put_env, [:riak_core, :schema_dirs, ['./priv']])

    # start our app
    rpc(node, Application, :ensure_all_started, [:no_slides])
    {:ok, node}
  end

  defp build_cluster(nodes) do
    # join remaining nodes to the ring on the first node
    [first | tail] = nodes
    for node <- tail do
      rpc(String.to_atom(node), :riak_core, :join, [String.to_atom(first)])
    end
  end

  defp rpc(node, module, function, args) do
    case :rpc.block_call(node, module, function, args) do
      {:ok, val} -> {:ok, val}
      :ok -> :ok
      err -> IO.puts "RPC error: #{inspect err}"
    end
  end

  defp inet_loader_args do
    to_charlist("-loader inet -hosts 127.0.0.1 -setcookie #{:erlang.get_cookie()}")
  end

  defp allow_boot(host) do
    {:ok, ipv4} = :inet.parse_ipv4_address(host)
    :erl_boot_server.add_slave(ipv4)
  end

  defp add_code_paths(node) do
    rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp node_name(node_host) do
    node_host
    |> to_string
    |> String.split("@")
    |> Enum.at(0)
    |> String.to_atom
  end
end
