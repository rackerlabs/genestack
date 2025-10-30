# Genestack Structure and Files

This document outlines the structure and purpose of the `/etc/genestack` directory, which serves as a central configuration location for Genestack, a platform for deploying and managing OpenStack and related services using Helm charts. It includes descriptions of the key subdirectories and the `helm-chart-versions.yaml` file.

## `/etc/genestack` Directory Overview

The `/etc/genestack` directory is the primary location for configuration files used by Genestack's deployment scripts. It contains Helm configuration overrides, custom settings, and version information for various services. The directory is organized to separate global configurations, service-specific configurations, and other operational settings.

### Subdirectories

#### `/etc/genestack/helm-configs`

This directory stores Helm configuration overrides for individual services and global settings. It is organized into subdirectories for each service, as well as a `global_overrides` directory for configurations that apply across multiple services.

- **Purpose**: Stores YAML files that override default Helm chart values for specific services or globally.
- **Structure**:
  - `/etc/genestack/helm-configs/global_overrides`: Contains YAML files with global Helm configuration overrides applied to all services. These settings are typically used to enforce consistent configurations across the deployment.
  - `/etc/genestack/helm-configs/<service_name>`: Each service (e.g., `keystone`, `nova`, `grafana`) has its own subdirectory containing service-specific override YAML files, such as `<service_name>-helm-overrides.yaml`. These files customize Helm chart settings for the respective service.
- **Usage**: The installation scripts (e.g., `install-<service_name>.sh`) reference these YAML files using the `-f` flag in Helm commands to customize deployments.

#### `/etc/genestack/kustomize`

This directory contains scripts and configurations for Kustomize, a tool used to customize Kubernetes manifests during deployment.

- **Purpose**: Houses the `kustomize.sh` script and related resources used as a post-renderer in Helm deployments to apply additional Kubernetes manifest transformations.
- **Structure**:
  - `/etc/genestack/kustomize/kustomize.sh`: A script invoked by Helm's `--post-renderer` flag to apply Kustomize transformations specific to each service's overlay (e.g., `keystone/overlay`, `nova/overlay`).
- **Usage**: Referenced in Helm commands to ensure consistent application of Kubernetes customization across services.

### `helm-chart-versions.yaml` File

The `helm-chart-versions.yaml` file, located at `/etc/genestack/helm-chart-versions.yaml`, is a critical configuration file that centralizes version information for all Helm charts used in the Genestack deployment.

- **Purpose**: Defines the specific versions of Helm charts for each service to ensure consistent and reproducible deployments.
- **Structure**: The file follows a YAML format with a `charts` key, under which each service is listed with its corresponding Helm chart version. For example:

  ```yaml
  charts:
    barbican: 2024.2.208+13651f45-628a320c
    ceilometer: 2024.2.115+13651f45-628a320c
    cinder: 2024.2.409+13651f45-628a320c
    envoy: v1.4.2
    fluentbit: 0.52.0
    glance: 2024.2.396+13651f45-628a320c
    gnocchi: 2024.2.50+628a320c
    grafana: 9.2.2
    heat: 2024.2.294+13651f45-628a320c
    horizon: 2024.2.264+13651f45-628a320c
    ironic: 2024.2.121+13651f45-628a320c
    keystone: 2024.2.386+13651f45-628a320c
    kube-event-exporter: 3.6.3
    kube-ovn: v1.13.14
    libvirt: 2024.2.92+628a320c
    longhorn: 1.8.0
    magnum: 2024.2.157+13651f45-628a320c
    mariadb-operator: 0.36.0
    masakari: 2024.2.17+13651f45-628a320c
    memcached: 7.8.6
    metallb: v0.13.12
    neutron: 2024.2.529+13651f45-628a320c
    nova: 2024.2.555+13651f45-628a320c
    octavia: 2024.2.30+13651f45-628a320c
    placement: 2024.2.62+13651f45-628a320c
    postgres-operator: 1.12.2
    prometheus: 70.4.2
    redis-operator: 0.21.0
  ```
- **Usage**: Installation scripts (e.g., `install-<service_name>.sh`) read this file to determine the correct Helm chart version for each service. The `ye(Yaml Editor)` script also uses this file to fetch the appropriate `values.yaml` file for a given service version when editing configurations.

## Additional Notes

- **Centralized Version Control**: The `helm-chart-versions.yaml` file ensures that all services use consistent versions, reducing the risk of version mismatches during deployments.
- **Override Precedence**: Configurations in `/etc/genestack/helm-configs/<service_name>` take precedence over those in `/opt/genestack/base-helm-configs/<service_name>`, allowing for flexible customization while maintaining baseline defaults.