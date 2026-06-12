# Genestack Structure and Files

This document outlines the structure and purpose of the `/etc/genestack` directory, which serves as a central configuration location for Genestack, a platform for deploying and managing OpenStack and related services using Helm charts.

## `/etc/genestack` Directory Overview

The `/etc/genestack` directory is the primary location for configuration files used by Genestack's deployment scripts. It contains Helm configuration overrides, custom settings, and version information.

### Subdirectories

#### `/etc/genestack/helm-configs`

This directory stores Helm configuration overrides for individual services and global settings.

- **Purpose**: Stores YAML files that override default Helm chart values for specific services or globally.
- **Structure**:
  - `/etc/genestack/helm-configs/global_overrides/`: Contains YAML files with global Helm configuration overrides applied to all services.
  - `/etc/genestack/helm-configs/<service_name>/`: Each service has its own subdirectory containing service-specific override YAML files, such as `<service_name>-helm-overrides.yaml`.
- **Usage**: The unified installer (`install.sh`) references these YAML files using the `-f` flag in Helm commands to customize deployments.

#### `/etc/genestack/kustomize/`

This directory contains scripts and configurations for Kustomize, a tool used to customize Kubernetes manifests during deployment.

- **Purpose**: Houses the `kustomize.sh` script and related resources used as a post-renderer in Helm deployments.
- **Structure**:
  - `/etc/genestack/kustomize/kustomize.sh`: A script invoked by Helm's `--post-renderer` flag to apply Kustomize transformations specific to each service's overlay (e.g., `nova/overlay`).
- **Usage**: Referenced automatically by `install.sh` when a service's config enables kustomize.

### `helm-chart-versions.yaml` File

The `helm-chart-versions.yaml` file, located at `/etc/genestack/helm-chart-versions.yaml`, centralizes version information for all Helm charts used in Genestack.

- **Purpose**: Defines the specific versions of Helm charts for each service to ensure consistent and reproducible deployments.
- **Structure**: A YAML file with a `charts` key, under which each service is listed with its version.
- **Usage**: `install.sh` reads this file to determine the correct Helm chart version. Service configs can override this per-service using the `version:` field.

## `/opt/genestack` Directory Overview

### `base-helm-configs/<service_name>/`

This directory holds the default Helm values files that ship with Genestack.

- **Purpose**: Provides baseline configuration values from the upstream charts, with Genestack-specific customizations layered on top.
- **Structure**: The default overrides for each service, such as `nova/helm-nova-overrides.yaml`.
- **Usage**: Automatically picked up by `install.sh` as the first `-f` argument in the Helm command.

## Override Precedence

The Helm override chain, from lowest to highest priority, is:

1. Upstream Helm chart defaults (from the chart itself)
2. `base-helm-configs/<svc>/` files (Genestack default values)
3. `global_overrides/*.yaml` (cluster-wide overrides)
4. `helm-configs/<svc>/` files (per-cluster overrides)
5. `--set` flags (injected secrets, user overrides)

Later files/values override earlier ones for the same key.

## Unified Installer

All services are installed via the single entry point `bin/install.sh`:

```bash
# Basic install
install.sh --service nova

# With helm flags passed through
install.sh --service nova --wait --timeout 30m

# Rotate secrets before install
install.sh --rotate-secrets --service nova

# Pre-flight check (fail if secrets missing)
install.sh --check-secrets --service nova
```

Service configuration lives in `bin/services/<name>.yaml` files (see `bin/services/nova.yaml` and `bin/services/example-service.yaml` for examples).
