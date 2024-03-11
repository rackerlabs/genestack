
The following example describes configuration options to send alerts via alertmanager to
Rackspace encore, the `Encore UUID` is derived by account where the secret `SECRET KEY` is
used per application submitting webhooks:

```yaml
global:
  resolve_timeout: 5m
receivers:
- name: default-receiver
- name: watchman-webhook
- name: critical-alert-manager-handler
  webhook_configs:
  - url: https://watchman.api.manage.rackspace.com/v1/mpk:<ENCORE UUID>/webhook/mpk-alertmanager?secret=<SECRET KEY>&severity=high
  - url: http://prometheus-msteams.rackspace-system.svc:2000/critical
- name: warning-alert-manager-handler
  webhook_configs:
    - url: http://prometheus-msteams.rackspace-system.svc:2000/warning
route:
  group_by:
  - alertname
  - severity
  - cluster
  - region
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 12h
  receiver: watchman-webhook
  routes:
  - match:
      severity: critical
    receiver: watchman-webhook
    routes:
    - match_re:
        namespace: kube-system|rackspace-system
      receiver: critical-alert-manager-handler
  #- match_re:
  #    severity: warning
  #  receiver: watchman-webhook
  #  routes:
  #  - match_re:
  #      namespace: kube-system|rackspace-system
  #    receiver: warning-alert-manager-handler
```
