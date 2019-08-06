use Mix.Config

 config :no_slides,
   nodes: [
    {"node1@127.0.0.1", 8198, 8199},
    {"node2@127.0.0.1", 8298, 8299},
    {"node3@127.0.0.1", 8398, 8399}
   ]
