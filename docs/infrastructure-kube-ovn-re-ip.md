# Re-IP Your Rackspace OpenStack Environment

When running an OpenStack-based environment, especially one that includes Kubernetes—you may encounter
scenarios where your existing IP space is too small or conflicts with other networks. In these cases,
you can re-IP your cloud by following the steps below. However, be aware that changing a subnet’s CIDR
disrupts existing services and requires Pods (or other components) to be rebuilt. Plan carefully to
minimize impact on production workloads.

!!! Important

    After changing the subnet CIDR, existing Pods will lose proper network access and must be rebuilt.
    We strongly recommend planning downtime or scheduling this operation during a maintenance window to
    avoid unexpected disruptions.

    These instructions only cover changing the CIDR for a subnet. If you need to update the Join subnet,
    please refer to [Change Join CIDR](https://kubeovn.github.io/docs/stable/en/ops/change-join-subnet)
    from the Kube-OVN documentation.

## Steps & Considerations

| **Step** | **Description** |
| -------- | --------------- |
| Plan Downtime | Because all existing Pods need to be rebuilt, schedule this change during a maintenance window or a low-traffic period. |
| Validate Services | After your Pods are back up, verify that services and applications are reachable on the new IP range. |
| Monitor & Log | Keep a close eye on logs, performance metrics, and network stability after re-IP to ensure everything returns to optimal functionality. |

For additional guidance, or if you have more complex networking requirements, contact your **Rackspace** support team. We’re here to help you build a resilient, scalable cloud environment tailored to your needs.

## Running the Maintenance

* Use `kubectl edit` to update the subnet’s `cidrBlock`, `gateway`, and `excludeIps`.

| Field | Description | Type |
| ----- | ----------- | ---- |
| `cidrBlock` | The new CIDR block for the subnet. | STRING |
| `gateway` | The gateway IP address for the subnet. | STRING |
| `excludeIps` | A list of IP addresses that should not be assigned to Pods. | ARRAY |

``` shell
kubectl edit subnets.kubeovn.io ovn-default
```

* Save and exit once you have updated the fields with the new CIDR information.

### Rebuild All Pods in the Updated Subnet

This example shows how to delete all Pods that are not using host-networking.

!!! genestack

    This command will have a significant impact on your environment, impacting all service APIs; however,
    none of the data will be lost and all of the dataplane traffic should not be impacted.

``` shell
for ns in $(kubectl get ns --no-headers -o custom-columns=NAME:.metadata.name); do
  for pod in $(kubectl get pod --no-headers -n "$ns" --field-selector spec.restartPolicy=Always -o custom-columns=NAME:.metadata.name,HOST:spec.hostNetwork | awk '{if ($2!="true") print $1}'); do
    kubectl delete pod "$pod" -n "$ns" --ignore-not-found --wait=False
  done
done
```

## Conclusion

After running the maintenance, your OpenStack environment should be re-IP’d and ready to handle your workloads.
If you encounter any issues or need further assistance, please reach out to your **Rackspace** support team for help.
