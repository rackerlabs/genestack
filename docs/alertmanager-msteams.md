# Microsoft Teams Alerts

The following example describes configuration options to send alerts via alertmanager to Microsoft Teams.

``` yaml
alertmanager:

  ## Alertmanager configuration directives
  ## ref: https://prometheus.io/docs/alerting/configuration/#configuration-file
  ##      https://prometheus.io/webtools/alerting/routing-tree-editor/
  ##
  config:
    global:
      resolve_timeout: 5m
    inhibit_rules:
      - source_matchers:
          - 'severity = critical'
        target_matchers:
          - 'severity =~ warning|info'
        equal:
          - 'namespace'
          - 'alertname'
      - source_matchers:
          - 'severity = warning'
        target_matchers:
          - 'severity = info'
        equal:
          - 'namespace'
          - 'alertname'
      - source_matchers:
          - 'alertname = InfoInhibitor'
        target_matchers:
          - 'severity = info'
        equal:
          - 'namespace'
      - target_matchers:
          - 'alertname = InfoInhibitor'
    route:
      group_by: ['namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 12h
      receiver: msteams_config
      routes:
        - receiver: 'null'
          matchers:
            - alertname = "Watchdog"
    receivers:
      - name: 'null'
      - name: 'msteams_config'
        msteams_configs:
        - send_resolved: true
          webhook_url: https://msteams.webhook_url.example
```
