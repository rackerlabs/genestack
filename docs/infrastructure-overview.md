# Infrastructure Deployment Demo

![Genestack Infra](assets/images/genstack-local-arch-k8s.svg)

## Infrastructure Overview

The full scale Genestack infrastructure is bound to change over time, however, the idea is to keep things simple and transparent. The above graphic highlights how we deploy our environments and what the overall makeup of our platforms are expected to look like.

!!! tip

    The infrastructure deployment can almost all be run in parallel. The above demo does everything serially to keep things consistent and easy to understand but if you just need to get things done, feel free to do it all at once.

## Deployment choices

When you're building the cloud, many of the underlying infrastructure components have a deployment choice of `base` or `aio`.

* `base` creates a production-ready environment that ensures an HA system is deployed across the hardware available in your cloud.
* `aio` creates a minimal cloud environment which is suitable for test, which may have low resources.

## Demo

[![asciicast](https://asciinema.org/a/629790.svg)](https://asciinema.org/a/629790)
