# Persistent Storage Demo

[![asciicast](https://asciinema.org/a/629785.svg)](https://asciinema.org/a/629785)

## Deploying Your Persistent Storage

For the basic needs of our Kubernetes environment, we need some basic persistent storage. Storage, like anything good in life,
is a choose your own adventure ecosystem, so feel free to ignore this section if you have something else that satisfies the need.

The basis needs of Genestack are the following storage classes

* general - a general storage cluster which is set as the deault.
* general-multi-attach - a multi-read/write storage backend

These `StorageClass` types are needed by various systems; however, how you get to these storage classes is totally up to you.
The following sections provide a means to manage storage and provide our needed `StorageClass` types. While there may be many
persistent storage options, not all of them are needed.
