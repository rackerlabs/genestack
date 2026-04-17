# Deploy Skyline

OpenStack Skyline is the next-generation web-based dashboard designed to provide a modern, responsive, and highly performant interface for managing OpenStack services. As an evolution of the traditional Horizon dashboard, Skyline focuses on improving user experience with a more streamlined and intuitive design, offering faster load times and enhanced responsiveness. It aims to deliver a more efficient and scalable way to interact with OpenStack components, catering to both administrators and end-users who require quick and easy access to cloud resources. In this document, we will cover the deployment of OpenStack Skyline using Genestack. Genestack ensures that Skyline is deployed effectively, allowing users to leverage its improved interface for managing both private and public cloud environments with greater ease and efficiency.

### Enable Federation (use Keystone public endpoint)

!!! tip

    Pause for a moment to consider if you will be wanting to access Skyline via the gateway-api controller over a specific FQDN. If so, adjust the gateway api definitions to suit your needs. For more information view [Gateway API](infrastructure-gateway-api.md)...

``` shell
/opt/genestack/bin/install-skyline.sh
```

## Customize configuration

Skyline configuration can be customized by creating override files in `/etc/genestack/helm-configs/skyline/`. Any YAML files in this directory will be applied during deployment with the highest precedence.

Example override file to customize resource limits:

```yaml
pod:
  resources:
    enabled: true
    skyline:
      requests:
        memory: "1024Mi"
        cpu: "200m"
      limits:
        memory: "4096Mi"
        cpu: "4000m"
```
