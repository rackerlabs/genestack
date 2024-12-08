#!/bin/bash
kubectl --namespace openstack apply -k /etc/genestack/kustomize/skyline/overlay $@
