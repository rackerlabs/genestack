# Run The Genestack Kubernetes Deployment

Genestack assumes Kubernetes is present and available to run workloads on. We don't really
care how your Kubernetes was deployed or what flavor of Kubernetes you're running. For our
purposes, we're using Kubespray, but you do you.

## Dependencies

The Genestack Kubernetes deployment platform has a few dependencies that will need to be
accounted for before running the deployment. The following dependencies are required:

* Kube-OVN
* Persistent Storage

While the Genestack Kubernetes deployment platform is designed to be flexible and work with
a variety of Kubernetes deployments, it is important to note that the platform is designed
to work with Kube-OVN and some form of persistent Storage. that all said, Genestack does
provide methods to manage the dependencies the platform requires; however, it is
important to understand that there will be some choices to be made.

## Demo

For a full end to end demo, see watching the following demonstration.

[![asciicast](https://asciinema.org/a/629780.svg)](https://asciinema.org/a/629780)
