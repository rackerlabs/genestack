# Run The Genestack Kubernetes Deployment

Genestack assumes Kubernetes is present and available to run workloads on. We don't really care how your Kubernetes was deployed or what flavor of Kubernetes you're running.
For our purposes we're using Kubespray, but you do you. We just need the following systems in your environment.

* Kube-OVN
* Persistent Storage
* MetalLB
* Ingress Controller

If you have those three things in your environment, you should be fully compatible with Genestack.

## Demo

[![asciicast](https://asciinema.org/a/629780.svg)](https://asciinema.org/a/629780)
