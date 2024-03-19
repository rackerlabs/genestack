# Slack Alerts

The following example describes configuration options to send alerts via alertmanager to slack
using a slack hook.

``` yaml
alertmanager:
  alertmanagerSpec:
    image:
      repository: docker.io/prom/alertmanager:v0.20.0
  config:
    global:
      resolve_timeout: 5m
    receivers:
    - name: default-receiver
    - name: watchman-webhook
    - name: warning-alert-manager-handler
      slack_configs:
      - api_url: https://hooks.slack.com/services/<slackwebhookhere>
        channel: '#<slack-channel here>'
        send_resolved: true
        text: >-
          {{- if .CommonAnnotations.summary -}}
            *Summary*: {{- .CommonAnnotations.summary -}}{{- "\n" -}}
          {{- else if .CommonAnnotations.description -}}
            *Description*: {{- .CommonAnnotations.description -}}{{- "\n" -}}
          {{- else if .CommonAnnotations.message -}}
            *Message*: {{- .CommonAnnotations.message -}}{{- "\n" -}}
          {{- end -}}
          *Cluster*: {{ .GroupLabels.cluster }}
          *Wiki*: https://desired.wiki.page/{{ .GroupLabels.alertname }}
    route:
      group_by:
      - alertname
      - severity
      - cluster
      - region
      group_interval: 5m
      group_wait: 10s
      receiver: watchman-webhook
      repeat_interval: 12h
      routes:
      - match_re:
          severity: critical
        receiver: warning-alert-manager-handler
```
