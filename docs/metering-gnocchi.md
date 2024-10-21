# Gnocchi (Metric Storage API)

Gnocchi is an open-source project designed to store and manage time series data.

It addresses the challenge of efficiently storing and indexing large-scale time
series data, which is crucial in modern cloud environments that are vast,
dynamic, and may serve multiple users. Gnocchi is built with performance,
scalability, and fault-tolerance in mind, without relying on complex storage
systems.

Unlike traditional time series databases that store raw data points and compute
aggregates (_like averages or minimums_) when queried, Gnocchi simplifies this
by pre-aggregating data during ingestion. This makes retrieving data much
faster since the system only needs to read the already processed results.

## Architecture

Gnocchi includes multiple services: an HTTP REST API, an optional
statsd-compatible daemon, and an asynchronous processing daemon
(_gnocchi-metricd_). Data is ingested through the API or statsd daemon,
while `gnocchi-metricd` handles background tasks like statistics computation and
metric cleanup.

![Gnocchi Architecture](assets/images/gnocchi-architecture.svg)

<figure>
   <figcaption>Image source: <a href="https://gnocchi.osci.io/intro.html" target="_blank" rel="noopener noreferrer">gnocchi.osci.io</a></figcaption>
</figure>

Gnocchi services are stateless thus can be scaled horizontally without much
effort. That being said, we can easily define an HPA (HorizontalPodAutoscaler)
policy to do just that for `ReplicaSet` components such as the `gnocchi-api`.
However, `metricd` and `statsd` components are configured to be
`DaemonSets`, so operators need only label additional nodes with the
configured node-selector key/value of `openstack-control-plane=enabled` to
scale those components up or down.

## Storage

As shown in the previous architecture diagram, Gnocchi relies on three key
external components for proper functionality:

 - Storage for incoming measures
 - Storage for aggregated metrics
 - An index

### Measures & Aggregates

Gnocchi supports various storage backends for incoming measures and aggregated
metrics, including:

 - File
 - Ceph (_flex default for `incoming` & `storage`_)
 - OpenStack Swift
 - Amazon S3
 - Redis

For smaller architectures, using the file driver to store data on disk may be
sufficient. However, S3, Ceph, and Swift offer more scalable storage options,
with Ceph being the recommended choice due to its better consistency. In
larger or busier deployments, a common recommendation is to use Redis for
incoming measure storage and Ceph for aggregate storage.

### Indexing

The indexer driver stores the index of all resources, archive policies, and
metrics, along with their definitions, types, and properties. It also handles
the linking of resources to metrics and manages resource relationships.
Supported drivers include the following:

 - PostgreSQL (_flex default_)
 - MySQL (_version 5.6.4 or higher_)

## Resource Types

The resource types that reside within Gnocchi are created during the Ceilometer
db-sync job which executes `ceilometer-upgrade`. We create the default types
that ship with Ceilometer, they can be modified via the Metrics API post
creation if necessary.

## REST API Usage

The Gnocchi REST API is well documented on their website, please see the
[REST API Usage](https://gnocchi.osci.io/rest.html) section for full detail.
Furthermore, there is a community supported Python client and SDK
installable via pip, aptly named [python-gnocchiclient](https://github.com/gnocchixyz/python-gnocchiclient).
It's worth noting, this is a required module for `openstack metric` commands
to function. See [OpenStack Metrics](openstack-metrics.md) for example CLI
usage.
