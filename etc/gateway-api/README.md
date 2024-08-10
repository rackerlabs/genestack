# Gateway API Resources

These files are intended to be modified before use. Therein are example
domains that can be replaced with your own custom domain before being
applied to your gateway resource.

## Patching the Gateway

```shell
kubectl patch -n nginx-gateway gateway flex-gateway --type='json' --patch-file gateway-patches.json
```

## Applying Gateway Routes

```yaml
kubectl apply -f gateway-routes.yaml
```
