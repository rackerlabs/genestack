# Gnocchi (Metric Storage API)

Gnocchi is an open-source project designed to store and manage time series data.

It addresses the challenge of efficiently storing and indexing large-scale time
series data, which is crucial in modern cloud environments that are vast,
dynamic, and may serve multiple users. Gnocchi is built with performance,
scalability, and fault-tolerance in mind, without relying on complex storage
systems.

Unlike traditional time series databases that store raw data points and compute
aggregates (like averages or minimums) when queried, Gnocchi simplifies this by
pre-aggregating data during ingestion. This makes retrieving data much faster
since the system only needs to read the already processed results.

![Gnocchi Architecture](assets/images/gnocchi-architecture.svg)

## Resource Types

stub

## Metricd

stub

## REST API Usage

The Metrics API is RESTful in nature, and has a community supported python
module aptly named [python-gnocchiclient](https://github.com/gnocchixyz/python-gnocchiclient)
