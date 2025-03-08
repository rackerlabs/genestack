# Quick Start Guide

This guide will walk you through the process of deploying a test environment for Genestack. This is a great way to get started
with the platform and to familiarize yourself with the deployment process. The following steps will guide you through the process
of deploying a test environment on an OpenStack cloud in a simple three node configuration that is hyper-converged.

## Build Script

The following script will deploy a hyperconverged lab environment on an OpenStack cloud. The script can be found at
[`scripts/hyperconverged-lab.sh`](https://raw.githubusercontent.com/rackerlabs/genestack/refs/heads/main/scripts/hyperconverged-lab.sh).

??? "View the Hyper-converged Lab Script"

    ``` shell
    --8<-- "scripts/hyperconverged-lab.sh"
    ```

## Overview

A simple reference architecture for a hyper-converged lab environment is shown below. This environment consists of three nodes
that are connected to a two networks. The networks are connected via a router that provides external connectivity.

``` mermaid
flowchart TB
    %% Define clusters/subgraphs for clarity
    subgraph Public_Network
        PF["Floating IP<br>(203.0.113.x)"]
    end

    subgraph Router
        TR["hyperconverged-router<br>(with external gateway)"]
    end

    subgraph Hyperconverged_Net
        TN["hyperconverged-net<br>(192.168.100.x)"]
    end

    subgraph Hyperconverged_Compute_Net
        TCN["hyperconverged-compute-net<br>(192.168.102.x)"]
    end

    %% Hyperconverged Nodes
    subgraph Node_0
        HPC0["hyperconverged-0"]
    end

    subgraph Node_1
        HPC1["hyperconverged-1"]
    end

    subgraph Node_2
        HPC2["hyperconverged-2"]
    end

    %% Connections
    PF --> TR
    TR --> TN

    TN -- mgmt port --> HPC0
    TN -- mgmt port --> HPC1
    TN -- mgmt port --> HPC2

    HPC0 -- compute port --> TCN
    HPC1 -- compute port --> TCN
    HPC2 -- compute port --> TCN
```

## Build Phases

The deployment script will perform the following steps:

- Create a new OpenStack router
- Create a new OpenStack networks
- Create a new OpenStack security groups
- Create a new OpenStack ports
- Create a new OpenStack keypair
- Create a new OpenStack instance
- Create a new OpenStack floating IP
- Execute the basic Genestack installation

## Post Deployment

After the deployment is complete, the script will output the internal and external floating IP address information.

With this information, operators can login to the Genestack instance and begin to explore the platform.

## Demo

[![asciicast](https://asciinema.org/a/706976.svg)](https://asciinema.org/a/706976)
