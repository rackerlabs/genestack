# Purpose

This document introduces traffic flow in _Genestack_ using OVN with DVR
  (distributed virtual routing). _Genestack_ has DVR on by default.

The analysis here assumes you have the public Internet configured as a Neutron
provider network directly routable from each compute node. This configuration
helps route network traffic efficiently because it doesn't mostly need to send
all Internet traffic through some centralized point, like a logical router that
exists only on one gateway node.

# Distributed Virtual Routing (DVR)

- OVN supports DVR.
  - This works similarly to DVR-type functionality for other Neutron ML2
    plugins, like ML2/OVS.
- _Genestack_ uses DVR by default.
- DVR works by distributing the functionality to implement OVN components like
  switches and routers (which get used to implement Neutron networks, etc.)
    - So you may have a logical router in OVN and find each compute nodes
      implements OVS flows so that the software-defined network infrastructure
      behaves as if the router exists
          - It places flows so that one compute node using the router could
            send traffic to another compute node using the router without using
            something like a gateway node.
          - Each compute node has the appropriate flows to send traffic that
            logically goes through the router straight from compute-to-compute
              - So the router itself doesn't exist in one single place (e.g., a
                gateway node, so the traffic doesn't get centralized and
                re-routed.)

# Creating a server on a private network and talking to another server on that network

- If you start by creating a network and a subnet, and then don't add an
  external gateway to the network, and put two instances on the network, you
  can see the traffic between the two instances go straight between the
  computes in the _Geneve_ tunnel between the computes.
- This doesn't involve running traffic through a gateway node.

# Routing of public Internet traffic

## Attaching a provider network with internet access straight to an instance

- You can create an instance directly attached to a Neutron provider network
  with Internet access, referred to here as "publicnet" for short.
- In this case, the instance directly has the publicnet IP.
    - Creating an instance directly attached to the publicnet at creation time
      bypasses the step of manually or separately creating a floating IP, as
      you see PUBLICNET=<public_ipv4> (or the network name) on the instance
      immediately after it gets created.
        - however, you don't have the ability to move the IP around as you
          would with a floating IP.
- When the instance sends publicnet traffic:
    - it doesn't route any traffic through a gateway node.
    - the traffic leaves the compute node's NICs un-encapsulated
    - traffic going to the instance's publicnet IP come to the compute node's
      NICs unencapulated
- This doesn't involve NAT like a floating IP.

## Creating a server on a private network attached to a router with a publicnet gateway without a floating IP

- Instances on a private network attached to a router with a gateway can reach
  the Internet that way.
    - While they don't have a public IP for incoming connections, you can still
      use this to send traffic bound for the Internet.
          - This could help with running updates (like `apt update`) for a lot
            lot of servers that don't really need a public IP for accepting
            connections.
- In this case, public traffic logically goes through the router, but
    - The traffic does get relayed through the gateway nodes
        - You can see it leaving the bond or public interfaces on the gateway
          node.

## Adding a floating IP to a server on a private network

- You must have the instance attached to a switch or network attached to a
  router with an external publicnet gateway to add a floating IP to the
  instance.
    - which you can contrast with specifying publicnet as a network attached to
      the server at creation time
    - which means you also need to add the private subnet to the router
- This effectively sets up 1:1 NAT between the floating IP and the private IP
  on the instance so that you can directly receive external traffic on the
  instance, although you haven't attached a port on publicnet itself to the
  instance.
    - The 1:1 NAT doesn't bypass anything like security group rules.
- In this case, you can see traffic with the public IP directly on the compute
  node's NICs
    - so OVS for the compute does the NAT
    - You can also see the traffic without the NAT when dumping the tap for
      the instance itself.
- Using a floating IP like this allows you to move the IP to another instance.
