#!/usr/bin/env bash
# This script mostly backs up cert-manager CRs
set -euo pipefail

DIR="/home/ubuntu/cert-manager-backup"
mkdir -p $DIR

kubectl get issuer,clusterissuer,certificate,certificaterequest,order,challenge -A -o yaml \
  > $DIR/cert-manager-crs.yaml

kubectl get secret -n cert-manager -o yaml \
  > $DIR/cert-manager-namespace-secrets.yaml

kubectl get secret --all-namespaces --field-selector type=kubernetes.io/tls -o yaml \
  > $DIR/all-tls-secrets.yaml
