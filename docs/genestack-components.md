# Product Component Matrix

The following components are part of the initial product release
and largely deployed with Helm+Kustomize against the K8s API (v1.28 and up).

| Group      | Component             | Status   |
|------------|-----------------------|----------|
| Kubernetes | Kubernetes            | Included |
| Kubernetes | Kubernetes Dashboard  | Included |
| Kubernetes | Cert-Manager          | Included |
| Kubernetes | MetaLB (L2/L3)        | Included |
| Kubernetes | Core DNS              | Included |
| Kubernetes | Nginx Gateway API     | Included |
| Kubernetes | Kube-Proxy (IPVS)     | Included |
| Kubernetes | Calico                | Optional |
| Kubernetes | Kube-OVN              | Included |
| Kubernetes | Helm                  | Included |
| Kubernetes | Kustomize             | Included |
| Kubernetes | ArgoCD                | Optional |
| OpenStack  | openVswitch (Helm)    | Optional |
| OpenStack  | mariaDB (Operator)    | Included |
| OpenStack  | rabbitMQ (Operator)   | Included |
| OpenStack  | memcacheD (Operator)  | Included |
| OpenStack  | Ceph Rook             | Optional |
| OpenStack  | iscsi/tgtd            | Included |
| OpenStack  | Aodh (Helm)           | Optional |
| OpenStack  | Ceilometer (Helm)     | Optional |
| OpenStack  | Keystone (Helm)       | Included |
| OpenStack  | Glance (Helm)         | Included |
| OpenStack  | Cinder (Helm)         | Included |
| OpenStack  | Nova (Helm)           | Included |
| OpenStack  | Neutron (Helm)        | Included |
| OpenStack  | Placement (Helm)      | Included |
| OpenStack  | Horizon (Helm)        | Included |
| OpenStack  | Skyline (Helm)        | Optional |
| OpenStack  | Heat (Helm)           | Included |
| OpenStack  | Designate (Helm)      | Optional |
| OpenStack  | Barbican (Helm)       | Included |
| OpenStack  | Octavia (Helm)        | Included |
| OpenStack  | Ironic (Helm)         | Optional |
| OpenStack  | Magnum (Helm)         | Optional |
| OpenStack  | Masakari (Helm)       | Optional |
| OpenStack  | Cloudkitty (Helm)     | Optional |
| OpenStack  | Blazar (Helm)         | Optional |
| OpenStack  | Freezer (Helm)        | Optional |
| OpenStack  | metal3.io             | Planned  |
| OpenStack  | PostgreSQL (Operator) | Included |
| OpenStack  | Consul                | Planned  |

Initial monitoring components consists of the following projects

| Group      | Component          | Status   |
|------------|--------------------|----------|
| Kubernetes | Prometheus         | Included |
| Kubernetes | Alertmanager       | Included |
| Kubernetes | Grafana            | Included |
| Kubernetes | Node Exporter      | Included |
| Kubernetes | Kube State Metrics | Included |
| Kubernetes | redfish Exporter   | Included |
| OpenStack  | OpenStack Exporter | Included |
| OpenStack  | RabbitMQ Exporter  | Included |
| OpenStack  | Mysql Exporter     | Included |
| OpenStack  | memcacheD Exporter | Included |
| OpenStack  | Postgres Exporter  | Included |
| Kubernetes | Thanos             | Optional |
