# Environment Architecture

Genestack is making use of some homegrown solutions, community operators, and OpenStack-Helm. Everything
in Genestack comes together to form cloud in a new and exciting way; all built with opensource solutions
to manage cloud infrastructure in the way you need it.

They say a picture is worth 1000 words, so here's a picture.

![Genestack Architecture Diagram](assets/images/diagram-genestack.png)

The idea behind Genestack is simple, build an Open Infrastructure system that unites Public and Private
clouds with a platform that is simple enough for the hobbyist yet capable of exceeding the needs of the
enterprise.

## Dependencies

Yes there are dependencies. This project is made up of several submodules which are the component
architecture of the Genestack ecosystem.

* Kubespray: The bit delivery mechanism for Kubernetes. While we're using Kubespray to deliver a production
  grade Kubernetes baremetal solution, we don't really care how Kubernetes gets there.
* MariaDB-Operator: Used to deliver MariaBD clusters
* OpenStack-Helm: The helm charts used to create an OpenStack cluster.
* OpenStack-Helm-Infra: The helm charts used to create infrastructure components for OpenStack.
* Rook: The Ceph storage solution du jour. This is optional component and only needed to manage Ceph
  when you want Ceph.
