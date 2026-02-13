# Designate Prometheus and Alerting Rules

Add additional alerting rules in /etc/genestack/helm-configs/kube-prometheus-stack/rules/designate_prometheus_rules.yaml
 

## Add extra rules for prometheus to scrape metrics

```bash
additionalPrometheusRulesMap:
  openstack-resource-alerts:
    groups:
      - name: Designate Resource Alerts
        rules:
          - alert: ZoneInError
            expr: openstack_designate_zone_status{status=~"ERROR"}
            labels:
              severity: critical
            annotations:
              summary: "Designate zone is in ERROR state"
              description: |
                The dns zone `{{`{{$labels.id}}`}}` is in ERROR state.
          - alert: RecordInError
            expr: openstack_designate_recordsets_status{status=~"ERROR"}
            labels:
              severity: warning
            annotations:
              summary: "Designate record in in ERROR state"
              description: |
                The recordset `{{`{{$labels.id}}`}}` in zone `{{`{{$labels.zone_id}}`}}` is in ERROR state
          - alert: DesignateDown
            expr: openstack_designate_up != 1
            labels:
              severity: critical
            annotations:
              summary: "Designate Service is down"
              description: |
                Designate service is down; please check the designate service logs to determine the cause of the issue
          - alert: ZoneInPending
            expr: openstack_designate_zone_status{status=~"PENDING"}
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Designate zone has been in PENDING state for over 5 mins"
              description: |
                The dns zone `{{`{{$labels.id}}`}}` has been in PENDING state for over 5 mins
          - alert: RecordInPending
            expr: openstack_designate_recordsets_status{status=~"PENDING"}
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Designate record has been in PENDING state for over 5 mins"
              description: |
                The dns zone `{{`{{$labels.id}}`}}` has been in PENDING state for over 5 mins
```


