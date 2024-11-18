# PagerDuty Alerts

The following example describes configuration options to send alerts via alertmanager to PagerDuty.

``` yaml
alertmanager:

  ## Alertmanager configuration directives
  ## ref: https://prometheus.io/docs/alerting/configuration/#configuration-file
  ##      https://prometheus.io/webtools/alerting/routing-tree-editor/
  ##
  config:
    global:
      resolve_timeout: 5m
      pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
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
      receiver: 'pagerduty-notifications'
      routes:
        - receiver: 'null'
          matchers:
            - alertname = "Watchdog"
    receivers:
      - name: 'null'
      - name: 'pagerduty-notifications'
        pagerduty_configs:
        - service_key: 0c1cc665a594419b6d215e81f4e38f7
          send_resolved: true
```
