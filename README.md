![Genestack](assets/images/genestack.png)

# Welcome to Genestack: Where Cloud Meets You

Genestack — where Kubernetes and OpenStack tango in the cloud. Imagine a waltz between systems that deploy
what you need.

## Documentation

Read the deployment and operations documentation

[Genestack Documentation](https://rackerlabs.github.io/genestack/)

## Included/Required Components

* Kubernetes:
    * etd: noSQL Store
    * Kube-OVN: OVN based CNI plugin
    * Dashboard: Always there to take the lead
    * MetalLB: L2/L3 (BGP) Load Balancer
    * CoreDNS: DNS Server
    * Ingress-NGINX: Network Proxy
    * Cert-Manager: X509-TLS Certificate Manager

* Operators:
    * MariaDB: SQL Database
    * RabbitMQ: Message Bus
    * Rook (Optional): Ceph software defined Storage
    * Memcached: in-memory cache

* OpenStack:
    * Cinder: Block Storage Service
    * Glance: Machine Images Service
    * Heat: Orchestration Service
    * Horizon: Dashboard
    * Keystone: Identity Service
    * Neutron: Software defined Networking
    * Nova: Compute Service
    * Placement: Compute Scheduling
    * Octavia: Load Balancing Service
    * openVswitch: Kernel based network switching, alternatively to OVN (OpenStack only)

A more complete list is available at [Project Components](docs/components.md)

### Symphony of Simplicity

Genestack conducts this orchestra of tech with style. Operators play the score, managing the complexity with
a flick of their digital batons. They unify the chaos, making scaling and management a piece of cake. Think
of it like a conductor effortlessly guiding a cacophony into a symphony.


### Hybrid Hilarity

Our hybrid capabilities aren’t your regular circus act. Picture a shared OVN fabric — a communal network
where workers multitask like pros. Whether it’s computing, storing, or networking, they wear multiple
hats in a hyperconverged circus or a grand full-scale enterprise cloud extravaganza.


### The Secret Sauce: Kustomize & Helm

Genestack’s inner workings are a blend dark magic — crafted with [Kustomize](https://kustomize.io) and
[Helm](https://helm.sh). It’s like cooking with cloud. Want to spice things up? Tweak the
`kustomization.yaml` files or add those extra 'toppings' using Helm's style overrides. However, the
platform is ready to go with batteries included.

Genestack is making use of some homegrown solutions, community operators, and OpenStack-Helm. Everything
in Genestack comes together to form cloud in a new and exciting way; all built with opensource solutions
to manage cloud infrastructure in the way you need it.

#### Dependencies

Yes there are dependencies. This project is made up of several submodules which are the component
architecture of the Genestack ecosystem.

* Kubespray: The bit delivery mechanism for Kubernetes. While we're using Kubespray to deliver a production
  grade Kubernetes baremetal solution, we don't really care how Kubernetes gets there.
* MariaDB-Operator: Used to deliver MariaBD clusters
* OpenStack-Helm: The helm charts used to create an OpenStack cluster.
* OpenStack-Helm-Infra: The helm charts used to create infrastructure components for OpenStack.
* Rook: The Ceph storage solution du jour. This is optional component and only needed to manage Ceph
  when you want Ceph.

### Environment Architecture

They say a picture is worth 1000 words, so here's a picture.

![Genestack Architecture Diagram](assets/images/diagram-genestack.png)
