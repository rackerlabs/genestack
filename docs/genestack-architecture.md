# Environment Architecture

Genestack is making use of some homegrown solutions, community operators, and OpenStack-Helm. Everything
in Genestack comes together to form cloud in a new and exciting way; all built with opensource solutions
to manage cloud infrastructure in the way you need it.

They say a picture is worth 1000 words, so here's a picture.

``` mermaid
flowchart LR
  %% ─── Class styles ───────────────────────────────────────────
  classDef storage fill:#fdf6e3,stroke:#657b83;
  class LONGHORN,ISCSI,RBD,NFS,STORLAYER,LOCALSTORLAYER storage;

  %% ─── External sources / Artifacts ───────────────────────────
  subgraph "Artifacts & External Input"
    direction TB
    INT["🌐 Internet"]
    A1(OCI Containers)
    A2(Git Repo)
    A3([Helm + Kustomize])
    A1 --> A3
    A2 --> A3
  end

  %% ─── Kubernetes control plane ───────────────────────────────
  subgraph "Kubernetes Control Plane"
    direction TB
    ETCD[(etcd)]
    K1[[K8s API Server]]
    ETCD --> K1
    A3 --> K1
  end

  %% ─── Ingress & CNI / Networking ─────────────────────────────
  subgraph "Ingress & CNI / Networking"
    direction TB
    GWAPI[[Gateway API]]
    CNI[CNI Plugin]
    NET[Kube-OVN]
    OVS["OVS/OVN&nbsp;Switch"]
    NETLAYER[[Networking Layer]]

    INT <--> |Ingress/Egress| GWAPI
    K1 --> GWAPI
    K1 --> CNI
    CNI --> NET
    NET --> OVS
    OVS --> NETLAYER
  end

  %% ─── Storage systems ────────────────────────────────────────
  subgraph "Storage Systems"
    direction TB
    CSI[CSI Plugin]
    LONGHORN[Longhorn]
    STORAGECHOICE{{Storage Driver}}
    ISCSI[iSCSI]
    RBD["RBD (Ceph)"]
    NFS[NFS]
    STORLAYER[[Network Storage]]
    LOCALSTORLAYER[[Local Storage]]

    K1 --> CSI
    CSI --> LONGHORN
    LONGHORN <-->|PVC| K1
    LONGHORN <--> |PVC Replication| STORLAYER
    LONGHORN <--> |PVC| LOCALSTORLAYER

    NETLAYER <--> STORAGECHOICE
    STORAGECHOICE --> ISCSI
    STORAGECHOICE --> RBD
    STORAGECHOICE --> NFS
    STORAGECHOICE --> |LVM| LOCALSTORLAYER

    ISCSI --> STORLAYER
    RBD   --> STORLAYER
    NFS   --> STORLAYER
  end

  %% ─── Observability stack ────────────────────────────────────
  subgraph "Observability"
    direction TB
    EXPORTER(Node / API Exporter)
    PROM(Prometheus)
    AM(Alertmanager)
    GRAF(Grafana)
    TICKET[Trouble-Ticket Sys]

    K1 --> EXPORTER
    EXPORTER --> PROM
    EXPORTER --> GRAF
    PROM --> GRAF
    PROM --> AM
    AM --> TICKET
  end

  %% ─── Provisioning & Operators ───────────────────────────────
  subgraph "K8s Operators & Backing DB/MQ"
    direction TB
    KOPS[K8s Operators]
    MQ[(rabbitMQ)]
    MARIADB[(Mariadb)]
    MEM[(memcacheD)]

    K1 --> KOPS
    KOPS --> MQ
    KOPS --> MARIADB
    KOPS --> MEM
  end

  %% ─── OpenStack integration ──────────────────────────────────
  subgraph "OpenStack Integration"
    direction TB
    OSAPI[(OpenStack API)]
    OSS[[OpenStack Services]]

    OSAPI --> OSS
    OSAPI --> EXPORTER
    OSAPI <--> GWAPI

    OSS <--> MQ
    OSS <--> MARIADB
    OSS <--> MEM
    OSS <--> |Cinder| STORAGECHOICE
    OSS <--> |Neutron| OVS
  end

  %% ─── Compute & identity layer ───────────────────────────────
  subgraph "Compute & Identity"
    direction TB
    IDENTITY[Keystone]
    LIBVIRT[libvirt]
    KVM["KVM (qemu)"]

    OSS --> |Nova Scheduling| LIBVIRT
    LIBVIRT --> |VMs| KVM
    KVM --> |vSwitch| OVS
    IDENTITY --> OSS
  end
```

The idea behind Genestack is simple, build an Open Infrastructure system that unites Public and Private
clouds with a platform that is simple enough for the hobbyist yet capable of exceeding the needs of the
enterprise.
