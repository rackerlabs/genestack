#!/bin/bash

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --create-namespace --namespace=prometheus --wait --timeout 10m \
  -f /opt/genestack/base-helm-configs/prometheus/prometheus-helm-overrides.yaml \
  -f /etc/genestack/helm-configs/prometheus/prometheus-helm-overrides.yaml \
  -f /opt/genestack/base-helm-configs/prometheus/alerting_rules.yaml \
  -f /etc/genestack/helm-configs/prometheus/alerting_rules.yaml \
  -f /opt/genestack/base-helm-configs/prometheus/alertmanager_config.yaml \
  -f /etc/genestack/helm-configs/prometheus/alertmanager_config.yaml \
  --post-renderer /opt/genestack/base-kustomize/kustomize.sh \
  --post-renderer-args prometheus/base
