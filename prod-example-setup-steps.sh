# Remote taint from control-plane nodes
kubectl taint nodes $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule-

# Label the storage nodes
kubectl label node $(kubectl get nodes | awk '/storage/ {print $1}') role=storage-node

# Label the openstack controllers
kubectl label node $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') openstack-control-plane=enabled

# Label the compute nodes
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-compute-node=enabled

# Label the network nodes
kubectl label node $(kubectl get nodes | awk '/network/ {print $1}') openstack-network-node=enabled

# With  OVN we need the compute nodes to be "network" nodes as well. While they will be configured for networking, they wont be gateways.
kubectl label node $(kubectl get nodes | awk '/compute/ {print $1}') openstack-network-node=enabled

# Label control-plane nodes as workers
kubectl label nodes $(kubectl get nodes -l 'node-role.kubernetes.io/control-plane' -o 'jsonpath={.items[*].metadata.name}') node-role.kubernetes.io/worker=worker

kubectl apply -f /tmp/metallb-openstack-service-lb.yaml

helm upgrade --install ingress-openstack ./ingress \
             --namespace=openstack \
             --wait \
             --timeout 120m  \
             -f /tmp/ingress-helm-overrides.yaml \
             -f /tmp/prod-example-openstack-overrides.yaml

kubectl --namespace openstack patch service ingress -p '{"metadata":{"annotations":{"metallb.universe.tf/allow-shared-ip": "openstack-external-svc", "metallb.universe.tf/address-pool": "openstack-external"}}}'
kubectl --namespace openstack patch service ingress -p '{"spec": {"type": "LoadBalancer"}}'

kubectl apply -f /tmp/keystone-mariadb-database.yaml
kubectl apply -f /tmp/keystone-rabbitmq-queue.yaml

cd ~/osh/openstack-helm

helm upgrade --install keystone ./keystone \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /opt/flex-rxt/helm-configs/keystone/keystone-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.keystone.password="$(kubectl --namespace openstack get secret keystone-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install glance ./glance \
    --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /tmp/glance-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.glance.password="$(kubectl --namespace openstack get secret glance-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.glance.password="$(kubectl --namespace openstack get secret glance-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.glance.password="$(kubectl --namespace openstack get secret glance-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
     -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install heat ./heat \
  --namespace=openstack \
    --timeout 120m \
    -f /tmp/heat-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat.password="$(kubectl --namespace openstack get secret heat-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_trustee.password="$(kubectl --namespace openstack get secret heat-trustee -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.heat_stack_user.password="$(kubectl --namespace openstack get secret heat-stack-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.heat.password="$(kubectl --namespace openstack get secret heat-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.heat.password="$(kubectl --namespace openstack get secret heat-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
     -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install cinder ./cinder \
  --namespace=openstack \
    --wait \
    --timeout 120m \
    -f /tmp/cinder-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install neutron ./neutron \
  --namespace=openstack \
    --timeout 120m \
    -f /tmp/neutron-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.designate.password="$(kubectl --namespace openstack get secret designate-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set conf.neutron.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-nb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.neutron.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-sb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_nb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-nb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    --set conf.plugins.ml2_conf.ovn.ovn_sb_connection="tcp:$(kubectl --namespace kube-system get endpoints ovn-sb -o jsonpath='{.subsets[0].addresses[0].ip}:{.subsets[0].ports[0].port}')" \
    -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install nova ./nova \
  --namespace=openstack \
    --timeout 120m \
    -f /tmp/nova-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.nova.password="$(kubectl --namespace openstack get secret nova-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.neutron.password="$(kubectl --namespace openstack get secret neutron-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.ironic.password="$(kubectl --namespace openstack get secret ironic-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.cinder.password="$(kubectl --namespace openstack get secret cinder-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_api.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db_cell0.auth.nova.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.admin.password="$(kubectl --namespace openstack get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_messaging.auth.nova.password="$(kubectl --namespace openstack get secret nova-rabbitmq-password -o jsonpath='{.data.password}' | base64 -d)" \
    -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh

helm upgrade --install placement ./placement --namespace=openstack \
  --namespace=openstack \
    --timeout 120m \
    -f /tmp/placement-helm-overrides.yaml \
    --set endpoints.identity.auth.admin.password="$(kubectl --namespace openstack get secret keystone-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.identity.auth.placement.password="$(kubectl --namespace openstack get secret placement-admin -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.admin.password="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.placement.password="$(kubectl --namespace openstack get secret placement-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    --set endpoints.oslo_db.auth.nova_api.password="$(kubectl --namespace openstack get secret nova-db-password -o jsonpath='{.data.password}' | base64 -d)" \
    -f /tmp/prod-example-openstack-overrides.yaml \
    --post-renderer /opt/flex-rxt/kustomize/keystone/kustomize.sh
