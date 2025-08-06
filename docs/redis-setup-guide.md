Redis Cluster Setup with Helm (OT-Container-Kit Redis Operator 0.21.0)
Redis Git hub Repository: https://github.com/OT-CONTAINER-KIT/redis-operator
Overview
Deploys a 6-pod Redis cluster (3 leaders, 3 followers) on an OpenStack Kubernetes cluster using Helm, integrated into Genestack base-helm-configs, distributed across 3 nodes.
Prerequisites

Kubernetes cluster with kubectl configured.
Helm installed.
Genestack repository cloned: git clone https://github.com/rackerlabs/genestack.git.

Deployment Steps

Ensure values.yaml is configured in genestack/base-helm-configs with:
leader.replicas: 3
follower.replicas: 3
storageClassName: general
persistenceEnabled: true


Create the override file: Save redis-operator-helm-overrides.yaml in /etc/genestack/helm-configs/redis-operator/ with the provided content.
Deploy the Redis operator and cluster:
Run: ./bin/install-redis-operator.sh
Optional: Customize CLUSTER_NAME: ./bin/install-redis-operator.sh CLUSTER_NAME=mycluster


Verify deployment: kubectl get pods -n redis-systems -o wide

Basic Testing

Verify Pods: kubectl get pods -n redis-systems -o wide
Expected: 6 pods across 3 nodes, e.g., redis-cluster-leader-0 on node-1, etc.


Cluster Health: Inside a pod (e.g., kubectl exec -it redis-cluster-leader-0 -n redis-systems -- /bin/sh), run redis-cli --cluster check 127.0.0.1:6379
Expected: cluster_state:ok


Read/Write: redis-cli --cluster call 127.0.0.1:6379 SET testkey testvalue and GET testkey
Expected: OK and testvalue


Replication: Write to leader, check follower with redis-cli --cluster call 127.0.0.1:6379 GET repltest
Expected: replvalue


Persistence: Set persistkey, restart pod, verify with GET persistkey
Expected: persistvalue


Logs: kubectl logs redis-cluster-leader-0 -n redis-systems
Expected: No critical errors


Customization

Use redis-operator-helm-overrides.yaml to adjust clusterName, namespace, or enable externalService for external access.
Example: Set externalService.enabled: true and serviceType: LoadBalancer for external connectivity.
