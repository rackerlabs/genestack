# Product Component Matrix

The following components are part of the initial product release
and largely deployed with Helm+Kustomize against the K8s API (v1.28 and up).
Some components are intially only installed with the public cloud based,
OpenStack Flex, service, while OpenStack Enterprise naturally provides a larger
variety of services:

| Group      | Component            | OpenStack Flex | OpenStack Enterprise |
|------------|----------------------|----------------|----------------------|
| Kubernetes | Kubernetes           | Required       | Required             |
| Kubernetes | Kubernetes Dashboard | Required       | Required             |
| Kubernetes | Cert-Manager         | Required       | Required             |
| Kubernetes | MetaLB (L2/L3)       | Required       | Required             |
| Kubernetes | Core DNS             | Required       | Required             |
| Kubernetes | Ingress Controller (Nginx) | Required       | Required             |
| Kubernetes | Kube-Proxy (IPVS)    | Required       | Required             |
| Kubernetes | Calico               | Optional       | Required             |
| Kubernetes | Kube-OVN             | Required       | Optional             |
| Kubernetes | Helm                 | Required       | Required             |
| Kubernetes | Kustomize            | Required       | Required             |
| OpenStack  | openVswitch (Helm)   | Optional       | Required             |
| OpenStack  | Galera (Operator)    | Required       | Required             |
| OpenStack  | rabbitMQ (Operator)  | Required       | Required             |
| OpenStack  | memcacheD (Operator) | Required       | Required             |
| OpenStack  | Ceph Rook            | Optional       | Required             |
| OpenStack  | iscsi/tgtd           | Required       | Optional             |
| OpenStack  | Keystone (Helm)      | Required       | Required             |
| OpenStack  | Glance (Helm)        | Required       | Required             |
| OpenStack  | Cinder (Helm)        | Required       | Required             |
| OpenStack  | Nova (Helm)          | Required       | Required             |
| OpenStack  | Neutron (Helm)       | Required       | Required             |
| OpenStack  | Placement (Helm)     | Required       | Required             |
| OpenStack  | Horizon (Helm)       | Required       | Required             |
| OpenStack  | Skyline (Helm)       | Optional       | Optional             |
| OpenStack  | Heat (Helm)          | Required       | Required             |
| OpenStack  | Designate (Helm)     | Optional       | Required             |
| OpenStack  | Barbican (Helm)      | Required       | Required             |
| OpenStack  | Octavia (Helm)       | Required       | Required             |
| OpenStack  | Ironic (Helm)        | Optional       | Required             |
| OpenStack  | metal3.io            | Optional       | Required             |

Initial monitoring componets consists of the following projects

| Group      | Component            | OpenStack Flex | OpenStack Enterprise |
|------------|----------------------|----------------|----------------------|
| Kubernetes | Prometheus           | Required       | Required             |
| Kubernetes | Thanos               | Required       | Required             |
| Kubernetes | Alertmanager         | Required       | Required             |
| Kubernetes | Grafana              | Required       | Required             |
| Kubernetes | Node Exporter        | Required       | Required             |
| Kubernetes | redfish Exporter     | Required       | Required             |
| OpenStack  | OpenStack Exporter   | Required       | Required             |

At a later stage these components will be added

| Group     | Component            | OpenStack Flex | OpenStack Enterprise |
|-----------|----------------------|----------------|----------------------|
| OpenStack | MongoDB              | Optional       | Required             |
| OpenStack | Aodh (Helm)          | Optional       | Required             |
| OpenStack | Ceilometer (Helm)    | Optional       | Required             |
| OpenStack | Masakari (Helm)      | Optional       | Required             |
