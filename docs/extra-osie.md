# OSIE Deployment

``` shell
helm upgrade --install osie osie/osie \
             --namespace=osie \
             --create-namespace \
             --wait \
             --timeout 120m \
             -f /etc/genestack/helm-configs/osie/osie-helm-overrides.yaml
```
