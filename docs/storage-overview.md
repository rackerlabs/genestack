---
hide:
  - footer
---

# Persistent Storage Overview

For the basic needs of our Kubernetes environment, we need some basic persistent storage. Storage, like anything good in life,
is a choose your own adventure ecosystem, so feel free to ignore this section if you have something else that satisfies the need.

## Deploying Your Persistent Storage

The basis needs of Genestack are the following storage classes

| Storage Type | Description |
|--------------|-------------|
| general | A general storage cluster which is set as the deault |
| general-multi-attach | A multi-read/write storage backend |

These `StorageClass` types are needed by various systems; however, how you get to these storage classes is totally up to you.
The following sections provide a means to manage storage and provide our needed `StorageClass` types. While there may be many
persistent storage options, not all of them are needed.

| Backend Storage Options |
|----------------|
| [Cephadm/ceph-ansible/Rook (Ceph) - External](storage-ceph-rook-external.md) |
| [Rook (Ceph) - In Cluster](storage-ceph-rook-internal.md) |
| [External Block - Bring Your Own Storage](storage-external-block.md) |
| [NFS - External](storage-nfs-external.md) |
| [TopoLVM - In Cluster](storage-topolvm.md) |
| [Longhorn - In Cluster](storage-longhorn.md) |

## Storage Deployment Demo

[![asciicast](https://asciinema.org/a/629785.svg)](https://asciinema.org/a/629785)
