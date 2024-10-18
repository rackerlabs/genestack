# Background

- This page describes OVN monitoring in _Genestack_.
- Most OVN monitoring in _Genestack_ comes from _Kube-OVN_'s model
    - As the _Kube-OVN_ documentation indicates, this includes both:
        - control plane information
        - data plane network quality information
    - _Kube-OVN_ has
     [instrumention](https://prometheus.io/docs/practices/instrumentation/)
     for _Promethus_
        - so _Genestack_ documentation directs installing the k8s _ServiceMonitors_
          so that _Promethus_ can discover these metrics.

## Links

- [_Genestack_ documentation on installing _Kube-OVN_ monitoring](./prometheus-kube-ovn.md)
  - As mentioned above, this simply installs the _ServiceMonitors_ so that
    _Prometheus_ in _Genestack_ can discover the metrics exported by _Kube-OVN_.
  - you can see the _ServiceMonitors_ installed
    [here](https://github.com/rackerlabs/genestack/tree/main/base-kustomize/prometheus-ovn)
        - in particular, it has _ServiceMonitors_ for components:
            - _kube-ovn-cni_
            - _kube-ovn-controller_
            - _kube-ovn-monitor_
            - _kube-ovn-pinger_

            You can see a architectural descriptions of these components
            [here](https://kubeovn.github.io/docs/stable/en/reference/architecture/#core-controller-and-agent)

- [_Kube-OVN User Guide's "Monitor and Dashboard"_ section](https://kubeovn.github.io/docs/stable/en/guide/prometheus-grafana/)
    - the information runs a bit sparse in the User Guide; note the reference
      manual link (in the User Guide itself, and next link here below) for more
      detailed information on the provided metrics.
- [_Kube-OVN Reference Manual "Metrics"_](https://kubeovn.github.io/docs/stable/en/reference/metrics/)
    - This describes the monitoring metrics provided by _Kube-OVN_

# Metrics

## Viewing the metrics

In a full _Genestack_ installation, you can view Prometheus metrics:

- by using _Prometheus_' UI
- by querying _Prometheus_' HTTPS API
- by using _Grafana_
    - In particular, _Kube-OVN_ provides pre-defined Grafana dashboards
      installed in _Genestack_.

Going in-depth on these would go beyond the scope of this document, but sections
below provide some brief coverage.

### Prometheus' data model

_Prometheus_' data model and design-for-scale tends to make interactive
[_PromQL_](https://prometheus.io/docs/prometheus/latest/querying/basics/)
queries cumbersome. In general usage, you will find that _Prometheus_ data works
better for feeding into other tools, like the _Alertmanager_ for alerting, and
_Grafana_ for visualization.

### Prometheus UI

A full _Genestack_ installation includes the _Prometheus UI_. The _Prometheus_
UI prominently displays a search bar that takes _PromQL_ expressions.

You can easily see the available _Kube-OVN_ metrics by opening the Metrics
Explorer (click the globe icon) and typing `kube_ovn_`.

While this has some limited utility for getting a low-level view of individual
metrics, you will generally find it more useful to look at the Grafana
dashboards as described below.

As mentioned above, the _Kube-OVN_ documentation details the collected metrics
[here](https://kubeovn.github.io/docs/stable/en/reference/metrics)

### Prometheus API

You will probably need a strong understanding of the Prometheus data model and
_PromQL_ to use the _Prometheus_ API directly, and will likely find little use
for using the API interactively.

However, where you have a working `kubectl`, you can do something like the
following to use `curl` on the Prometheus API with minor adaptations for your
installation:

```
# Run kubectl proxy in the background
kubectl proxy &

# You will probably find the -g/--globoff option to curl useful to stop curl
# itself from interpreting the characters {} [] in URLs.
#
# Additionally, these characters technically require escaping in URLs, so you
# might want to use --data-urlencode

curl -sS -gG \
http://localhost:8001/api/v1/namespaces/prometheus/services/prometheus-operated:9090/proxy/api/v1/query \
--data-urlencode 'query=kube_ovn_ovn_status' | jq .
```

### Grafana

As mentioned previously, _Kube-OVN_ provides various dashboards with
information on both the control plane and the data plane network quality.

These dashboards contain a lot of information, so in many cases, you will likely
use them for troubleshooting by expanding to a large timeframe to see when
irregularities may have started occurring.

You can see the documentation from _Kube-OVN_ on these dashboards
[here](https://kubeovn.github.io/docs/stable/en/guide/prometheus-grafana/)

Some additional details on each of these dashboards follows.

#### Controller dashboard

In a typical _Genestack_ installation, you should see 3 controllers up here.
The dashboard displays the number of up controllers prominently.

The graphs show information about the `kube-ovn-controller` pods in the
`kube-system` namespace, mostly identified by their ClusterIP on the k8s
service network. You can typically see them along with the ClusterIPs that
identify them individually on the dashboard like:

```
kubectl -n kube-system get pod -l app=kube-ovn-controller -o wide
```

#### Kube-OVN-CNI dashboard

In this case, CNI refers to k8s' _container network interface_ which allows
k8s to use various plugins (such as _Kube-OVN_) for cluster networking, as
described [here](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-cni)

Like the Controller dashboard, it displays the number of pods up prominently.
It should have 1 pod for each k8s node, so it should match the count of your
k8s nodes:

```
# tail to skip header lines
kubectl get node | tail -n +2 | wc -l
```

These metrics belong to the 'control plane' metrics, and this dashboard will
probably work well by using a large timeframe to find anomalous behavior as
previously described.

#### OVN dashboard

This dashboard displays some metrics from the OVN, like the number of logical
switches and logical ports. It shows a chassis count that should match the
number of nodes in your cluster, and a flag (or technically a count, but you
will see "1") for "OVN DB Up".

This dashboard looks useful as previously described for looking for anomalous
behavior that emerged across a timeframe.

#### OVS dashboard

This dashboard displays information from OVS from each k8s node.

It sometimes uses names, but sometimes pod IPs.

OVS activity across nodes might not necessarily have a strong correlation, so
on this dashboard, you might take particular note that you can click the node
of interest on the legend for each graph, or choose a particular instance for
all of the graphs at the top.

You may need to collate the ClusterIPs with a node, which you can do with
something like:

```
kubectl get node -n kube-system -o wide | grep 10.10.10.10
```

which will display the name of the node with the pinger pod.
[kube-ovn-pinger](https://kubeovn.github.io/docs/stable/en/reference/architecture/#kube-ovn-pinger)
collects OVS status information, so while you see the `pinger` pod when checking
the IP, the information from the dashboard may *come from* the pinger pod, but
*pertains to* OVS, *not* the pinger pod.

#### Pinger dashboard

This dashboard prominently displays the OVS up count, OVN-Controller up count,
and API server accessible count. These should all have the same number, equal to
your number of nodes.

##### Inconsistent port binding nums

The _Kube-OVN_ documentation for this metric says "The number of mismatch port
bindings between ovs and ovn-sb" and provides no additional information.
However, in _Genestack_, you find ovn metadata 'localport' types in the NB that
don't need an SB binding, which increases this count. _Kube-OVN_'s OVN itself
often gets used for k8s alone and would in that case often have a 0 count here,
but _Genestack_ uses _OpenStack Neutron_ as a second CMS for _Kube-OVN_'s OVN
installation, resulting in the existence of ports that increase this count but
don't indicate a problem, so _Genestack_ will generally have a significant
count for each compute node for this metric.
