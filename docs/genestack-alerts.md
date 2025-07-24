<a name="top"></a>
<p style="font-size: 28px; font-weight: bold;">Genestack Prometheus Alerts</p>

## Blackbox Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **Service Down** | Service probe has failed for more than two minutes on (instance &#123;&#123; $labels.instance &#125;&#125;) | Service probe has failed for more than two minutes.<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | critical |
| **TLS certificate expiring** | SSL certificate will expire soon on (instance &#123;&#123; $labels.instance &#125;&#125;) | SSL certificate expires within 30 days.<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | warning |
| **TLS certificate expiring** | SSL certificate will expire soon on (instance &#123;&#123; $labels.instance &#125;&#125;) | SSL certificate expires within 15 days.<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Compute Resource Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **AbnormalInstanceFailures** | Instance build failure rate is abnormally high | This indicates a major problem building compute instances.<br>View logs and take action to resolve the build failures.<br> | critical |
| **InstancesStuckInFailureState** | Instances stuck in failure state for a prolonged period | There are instances stuck in a building or error state for a prolonged period<br>that need to be cleaned up.<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Image Resource Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **AbnormalImageFailures** | Image create failure rate is abnormally high | This indicates a major problem creating images.<br>View logs and take action to resolve the build failures.<br> | critical |
| **ImagesStuckInFailureState** | Images stuck in failure state for a prolonged period | There are images stuck in a failure state for a prolonged period<br>that need to be cleaned up.<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Linux MDM device and RAID alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **NodeMdInfoFailedDeviceCritical** | NVME device on Linux software RAID failure info | &#123;&#123; $labels.name &#125;&#125;<br>Number MD Failed:&#123;&#123; $labels.FailedDevices &#125;&#125;<br>LABELS: &#123;&#123; $labels &#125;&#125; | critical |
| **NodeMdInfoStateCritical** | Linux software MD RAID State is NOT active\|clean | &#123;&#123; $labels.name &#125;&#125;<br>State:&#123;&#123; $labels.State &#125;&#125;<br>LABELS: &#123;&#123; $labels &#125;&#125; | critical |
| **NodeMdInfoSuperblockPersistenceCritical** | Linux software MD Superblock is NOT persistent | &#123;&#123; $labels.name &#125;&#125;<br>Persistence:&#123;&#123; $labels.Persistence &#125;&#125;<br>LABELS: &#123;&#123; $labels &#125;&#125; | critical |
| **NodeMdStateCritical** | Linux MDM RAID State is &#123;&#123; $labels.state &#125;&#125; | &#123;&#123; $labels.name &#125;&#125;<br>MD RAID status:&#123;&#123; $value &#125;&#125;<br>MD RAID device:&#123;&#123; $labels.device &#125;&#125;<br>LABELS: &#123;&#123; $labels &#125;&#125; | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## MariaDB backup alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **mariadbBackupCritical** | Second successive MariaDB backup not successful within 1 hour of scheduled run | Second successive MariaDB backup not successful within 1 hour of scheduled run.<br> | critical |
| **mariadbBackupWarning** | Last MariaDB backup not successful within 1 hour of scheduled run | Last MariaDB backup not successful within 1 hour of scheduled run.<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Multipath path checker alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **NodeDmpathInfoMultipathCritical** | Multipathd paths are NOT active\|ready and paths are likely orphaned | &#123;&#123; $labels.name &#125;&#125;<br>labels: &#123;&#123; $labels &#125;&#125; | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Mysql Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **MysqlDown** | MariaDB down (instance &#123;&#123; $labels.instance &#125;&#125;) | MariaDB instance is down on &#123;&#123; $labels.instance &#125;&#125;<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | critical |
| **MysqlRestarted** | MySQL restarted (instance &#123;&#123; $labels.instance &#125;&#125;) | MySQL has just been restarted, less than one minute ago on &#123;&#123; $labels.instance &#125;&#125;.<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | info |
| **MysqlSlowQueries** | MySQL slow queries (instance &#123;&#123; $labels.instance &#125;&#125;) | MySQL server has some new slow queries.<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | warning |
| **MysqlTooManyConnections(>80%)** | Database too many connections (> 90%) (instance &#123;&#123; $labels.instance &#125;&#125;) | More than 90% of MySQL connections are in use on &#123;&#123; $labels.instance &#125;&#125;<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## OVN backup alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **ovnBackupDiskUsageCritical** | OVN backup volume >= 90% disk usage | OVN backup volume >= 90% disk usage.<br> | critical |
| **ovnBackupDiskUsageWarning** | OVN backup volume >= 80% disk usage | OVN backup volume >= 80% disk usage.<br> | warning |
| **ovnBackupUploadCritical** | Second successive OVN backup not uploaded within 1 hour of scheduled run | Second successive OVN backup not uploaded within 1 hour of scheduled run.<br> | critical |
| **ovnBackupUploadWarning** | Last OVN backup not uploaded within 1 hour of scheduled run | Last OVN backup not uploaded within 1 hour of scheduled run.<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Octavia Resource Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **LoadbalancersInError** | Loadbalancer stuck in error state for a prolonged period | This may indicate a potential problem with failover and/or health manager services.<br>This could also indicate other problems building load balancers in general.<br> | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## Volume Alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubernetesVolumeOutOfDiskSpace** | Kubernetes Volume out of disk space (instance &#123;&#123; $labels.instance &#125;&#125;) | Volume is almost full (< 20% left).<br>VALUE = &#123;&#123; $value &#125;&#125;<br>LABELS = &#123;&#123; $labels &#125;&#125;<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## alertmanager.rules
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **AlertmanagerClusterCrashlooping** | Half or more of the Alertmanager instances within the same cluster are crashlooping. | &#123;&#123; $value \| humanizePercentage &#125;&#125; of Alertmanager instances within the &#123;&#123;$labels.job&#125;&#125; cluster have restarted at least 5 times in the last 10m. | critical |
| **AlertmanagerClusterDown** | Half or more of the Alertmanager instances within the same cluster are down. | &#123;&#123; $value \| humanizePercentage &#125;&#125; of Alertmanager instances within the &#123;&#123;$labels.job&#125;&#125; cluster have been up for less than half of the last 5m. | critical |
| **AlertmanagerClusterFailedToSendAlerts** | All Alertmanager instances in a cluster failed to send notifications to a critical integration. | The minimum notification failure rate to &#123;&#123; $labels.integration &#125;&#125; sent from any instance in the &#123;&#123;$labels.job&#125;&#125; cluster is &#123;&#123; $value \| humanizePercentage &#125;&#125;. | critical |
| **AlertmanagerClusterFailedToSendAlerts** | All Alertmanager instances in a cluster failed to send notifications to a non-critical integration. | The minimum notification failure rate to &#123;&#123; $labels.integration &#125;&#125; sent from any instance in the &#123;&#123;$labels.job&#125;&#125; cluster is &#123;&#123; $value \| humanizePercentage &#125;&#125;. | warning |
| **AlertmanagerConfigInconsistent** | Alertmanager instances within the same cluster have different configurations. | Alertmanager instances within the &#123;&#123;$labels.job&#125;&#125; cluster have different configurations. | critical |
| **AlertmanagerFailedReload** | Reloading an Alertmanager configuration has failed. | Configuration has failed to load for &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod&#125;&#125;. | critical |
| **AlertmanagerFailedToSendAlerts** | An Alertmanager instance failed to send notifications. | Alertmanager &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod&#125;&#125; failed to send &#123;&#123; $value \| humanizePercentage &#125;&#125; of notifications to &#123;&#123; $labels.integration &#125;&#125;. | warning |
| **AlertmanagerMembersInconsistent** | A member of an Alertmanager cluster has not found all other cluster members. | Alertmanager &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod&#125;&#125; has only found &#123;&#123; $value &#125;&#125; members of the &#123;&#123;$labels.job&#125;&#125; cluster. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## config-reloaders
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **ConfigReloaderSidecarErrors** | config-reloader sidecar has not had a successful reload for 10m | Errors encountered while the &#123;&#123;$labels.pod&#125;&#125; config-reloader sidecar attempts to sync config in &#123;&#123;$labels.namespace&#125;&#125; namespace.<br>As a result, configuration for service running in &#123;&#123;$labels.pod&#125;&#125; may be stale and cannot be updated anymore. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## etcd
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **etcdDatabaseHighFragmentationRatio** | etcd database size in use is less than 50% of the actual allocated storage. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": database size in use on instance &#123;&#123; $labels.instance &#125;&#125; is &#123;&#123; $value \| humanizePercentage &#125;&#125; of the actual allocated disk space, please run defragmentation (e.g. etcdctl defrag) to retrieve the unused fragmented disk space. | warning |
| **etcdDatabaseQuotaLowSpace** | etcd cluster database is running full. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": database size exceeds the defined quota on etcd instance &#123;&#123; $labels.instance &#125;&#125;, please defrag or increase the quota as the writes to etcd will be disabled when it is full. | critical |
| **etcdExcessiveDatabaseGrowth** | etcd cluster database growing very fast. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": Predicting running out of disk space in the next four hours, based on write observations within the past four hours on etcd instance &#123;&#123; $labels.instance &#125;&#125;, please check as it might be disruptive. | warning |
| **etcdGRPCRequestsSlow** | etcd grpc requests are slow | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": 99th percentile of gRPC requests is &#123;&#123; $value &#125;&#125;s on etcd instance &#123;&#123; $labels.instance &#125;&#125; for &#123;&#123; $labels.grpc_method &#125;&#125; method. | critical |
| **etcdHighCommitDurations** | etcd cluster 99th percentile commit durations are too high. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": 99th percentile commit durations &#123;&#123; $value &#125;&#125;s on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | warning |
| **etcdHighFsyncDurations** | etcd cluster 99th percentile fsync durations are too high. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": 99th percentile fsync durations are &#123;&#123; $value &#125;&#125;s on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | warning |
| **etcdHighFsyncDurations** | etcd cluster 99th percentile fsync durations are too high. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": 99th percentile fsync durations are &#123;&#123; $value &#125;&#125;s on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | critical |
| **etcdHighNumberOfFailedGRPCRequests** | etcd cluster has high number of failed grpc requests. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": &#123;&#123; $value &#125;&#125;% of requests for &#123;&#123; $labels.grpc_method &#125;&#125; failed on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | warning |
| **etcdHighNumberOfFailedGRPCRequests** | etcd cluster has high number of failed grpc requests. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": &#123;&#123; $value &#125;&#125;% of requests for &#123;&#123; $labels.grpc_method &#125;&#125; failed on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | critical |
| **etcdHighNumberOfFailedProposals** | etcd cluster has high number of proposal failures. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": &#123;&#123; $value &#125;&#125; proposal failures within the last 30 minutes on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | warning |
| **etcdHighNumberOfLeaderChanges** | etcd cluster has high number of leader changes. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": &#123;&#123; $value &#125;&#125; leader changes within the last 15 minutes. Frequent elections may be a sign of insufficient resources, high network latency, or disruptions by other components and should be investigated. | warning |
| **etcdInsufficientMembers** | etcd cluster has insufficient number of members. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": insufficient members (&#123;&#123; $value &#125;&#125;). | critical |
| **etcdMemberCommunicationSlow** | etcd cluster member communication is slow. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": member communication with &#123;&#123; $labels.To &#125;&#125; is taking &#123;&#123; $value &#125;&#125;s on etcd instance &#123;&#123; $labels.instance &#125;&#125;. | warning |
| **etcdMembersDown** | etcd cluster members are down. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": members are down (&#123;&#123; $value &#125;&#125;). | warning |
| **etcdNoLeader** | etcd cluster has no leader. | etcd cluster "&#123;&#123; $labels.job &#125;&#125;": member &#123;&#123; $labels.instance &#125;&#125; has no leader. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## fluentbit serviceMonitor alert
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **MissingFluentbitServiceMonitor** | ServiceMonitor 'fluentbit-fluent-bit' is either down or missing. | Check if the Fluentbit ServiceMonitor is properly configured and deployed.<br> | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## general.rules
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **InfoInhibitor** | Info-level alert inhibition. | This is an alert that is used to inhibit info alerts.<br>By themselves, the info-level alerts are sometimes very noisy, but they are relevant when combined with<br>other alerts.<br>This alert fires whenever there's a severity="info" alert, and stops firing when another alert with a<br>severity of 'warning' or 'critical' starts firing on the same namespace.<br>This alert should be routed to a null receiver and configured to inhibit alerts with severity="info".<br> | none |
| **TargetDown** | One or more targets are unreachable. | &#123;&#123; printf "%.4g" $value &#125;&#125;% of the &#123;&#123; $labels.job &#125;&#125;/&#123;&#123; $labels.service &#125;&#125; targets in &#123;&#123; $labels.namespace &#125;&#125; namespace are down. | warning |
| **Watchdog** | An alert that should always be firing to certify that Alertmanager is working properly. | This is an alert meant to ensure that the entire alerting pipeline is functional.<br>This alert is always firing, therefore it should always be firing in Alertmanager<br>and always fire against a receiver. There are integrations with various notification<br>mechanisms that send a notification when this alert is not firing. For example the<br>"DeadMansSnitch" integration in PagerDuty.<br> | none |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kube-apiserver-slos
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeAPIErrorBudgetBurn** | The API server is burning too much error budget. | The API server is burning too much error budget on cluster &#123;&#123; $labels.cluster &#125;&#125;. | critical |
| **KubeAPIErrorBudgetBurn** | The API server is burning too much error budget. | The API server is burning too much error budget on cluster &#123;&#123; $labels.cluster &#125;&#125;. | critical |
| **KubeAPIErrorBudgetBurn** | The API server is burning too much error budget. | The API server is burning too much error budget on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeAPIErrorBudgetBurn** | The API server is burning too much error budget. | The API server is burning too much error budget on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kube-state-metrics
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeStateMetricsListErrors** | kube-state-metrics is experiencing errors in list operations. | kube-state-metrics is experiencing errors at an elevated rate in list operations. This is likely causing it to not be able to expose metrics about Kubernetes objects correctly or at all. | critical |
| **KubeStateMetricsShardingMismatch** | kube-state-metrics sharding is misconfigured. | kube-state-metrics pods are running with different --total-shards configuration, some Kubernetes objects may be exposed multiple times or not exposed at all. | critical |
| **KubeStateMetricsShardsMissing** | kube-state-metrics shards are missing. | kube-state-metrics shards are missing, some Kubernetes objects are not being exposed. | critical |
| **KubeStateMetricsWatchErrors** | kube-state-metrics is experiencing errors in watch operations. | kube-state-metrics is experiencing errors at an elevated rate in watch operations. This is likely causing it to not be able to expose metrics about Kubernetes objects correctly or at all. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-apps
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeContainerWaiting** | Pod container waiting longer than 1 hour | pod/&#123;&#123; $labels.pod &#125;&#125; in namespace &#123;&#123; $labels.namespace &#125;&#125; on container &#123;&#123; $labels.container&#125;&#125; has been in waiting state for longer than 1 hour. (reason: "&#123;&#123; $labels.reason &#125;&#125;") on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDaemonSetMisScheduled** | DaemonSet pods are misscheduled. | &#123;&#123; $value &#125;&#125; Pods of DaemonSet &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.daemonset &#125;&#125; are running where they are not supposed to run on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDaemonSetNotScheduled** | DaemonSet pods are not scheduled. | &#123;&#123; $value &#125;&#125; Pods of DaemonSet &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.daemonset &#125;&#125; are not scheduled on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDaemonSetRolloutStuck** | DaemonSet rollout is stuck. | DaemonSet &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.daemonset &#125;&#125; has not finished or progressed for at least 15m on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDeploymentGenerationMismatch** | Deployment generation mismatch due to possible roll-back | Deployment generation for &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.deployment &#125;&#125; does not match, this indicates that the Deployment has failed but has not been rolled back on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDeploymentReplicasMismatch** | Deployment has not matched the expected number of replicas. | Deployment &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.deployment &#125;&#125; has not matched the expected number of replicas for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeDeploymentRolloutStuck** | Deployment rollout is not progressing. | Rollout of deployment &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.deployment &#125;&#125; is not progressing for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeHpaMaxedOut** | HPA is running at max replicas | HPA &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.horizontalpodautoscaler  &#125;&#125; has been running at max replicas for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeHpaReplicasMismatch** | HPA has not matched desired number of replicas. | HPA &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.horizontalpodautoscaler  &#125;&#125; has not matched the desired number of replicas for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeJobFailed** | Job failed to complete. | Job &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.job_name &#125;&#125; failed to complete. Removing failed job after investigation should clear this alert on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeJobNotCompleted** | Job did not complete in time | Job &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.job_name &#125;&#125; is taking more than &#123;&#123; "43200" \| humanizeDuration &#125;&#125; to complete on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubePodCrashLooping** | Pod is crash looping. | Pod &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod &#125;&#125; (&#123;&#123; $labels.container &#125;&#125;) is in waiting state (reason: "CrashLoopBackOff") on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubePodNotReady** | Pod has been in a non-ready state for more than 15 minutes. | Pod &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod &#125;&#125; has been in a non-ready state for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeStatefulSetGenerationMismatch** | StatefulSet generation mismatch due to possible roll-back | StatefulSet generation for &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.statefulset &#125;&#125; does not match, this indicates that the StatefulSet has failed but has not been rolled back on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeStatefulSetReplicasMismatch** | StatefulSet has not matched the expected number of replicas. | StatefulSet &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.statefulset &#125;&#125; has not matched the expected number of replicas for longer than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeStatefulSetUpdateNotRolledOut** | StatefulSet update has not been rolled out. | StatefulSet &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.statefulset &#125;&#125; update has not been rolled out on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-resources
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **CPUThrottlingHigh** | Processes experience elevated CPU throttling. | &#123;&#123; $value \| humanizePercentage &#125;&#125; throttling of CPU in namespace &#123;&#123; $labels.namespace &#125;&#125; for container &#123;&#123; $labels.container &#125;&#125; in pod &#123;&#123; $labels.pod &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | info |
| **KubeCPUOvercommit** | Cluster has overcommitted CPU resource requests. | Cluster &#123;&#123; $labels.cluster &#125;&#125; has overcommitted CPU resource requests for Pods by &#123;&#123; $value &#125;&#125; CPU shares and cannot tolerate node failure. | warning |
| **KubeCPUQuotaOvercommit** | Cluster has overcommitted CPU resource requests. | Cluster &#123;&#123; $labels.cluster &#125;&#125;  has overcommitted CPU resource requests for Namespaces. | warning |
| **KubeMemoryOvercommit** | Cluster has overcommitted memory resource requests. | Cluster &#123;&#123; $labels.cluster &#125;&#125; has overcommitted memory resource requests for Pods by &#123;&#123; $value \| humanize &#125;&#125; bytes and cannot tolerate node failure. | warning |
| **KubeMemoryQuotaOvercommit** | Cluster has overcommitted memory resource requests. | Cluster &#123;&#123; $labels.cluster &#125;&#125;  has overcommitted memory resource requests for Namespaces. | warning |
| **KubeQuotaAlmostFull** | Namespace quota is going to be full. | Namespace &#123;&#123; $labels.namespace &#125;&#125; is using &#123;&#123; $value \| humanizePercentage &#125;&#125; of its &#123;&#123; $labels.resource &#125;&#125; quota on cluster &#123;&#123; $labels.cluster &#125;&#125;. | info |
| **KubeQuotaExceeded** | Namespace quota has exceeded the limits. | Namespace &#123;&#123; $labels.namespace &#125;&#125; is using &#123;&#123; $value \| humanizePercentage &#125;&#125; of its &#123;&#123; $labels.resource &#125;&#125; quota on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeQuotaFullyUsed** | Namespace quota is fully used. | Namespace &#123;&#123; $labels.namespace &#125;&#125; is using &#123;&#123; $value \| humanizePercentage &#125;&#125; of its &#123;&#123; $labels.resource &#125;&#125; quota on cluster &#123;&#123; $labels.cluster &#125;&#125;. | info |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-storage
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubePersistentVolumeErrors** | PersistentVolume is having issues with provisioning. | The persistent volume &#123;&#123; $labels.persistentvolume &#125;&#125; &#123;&#123; with $labels.cluster -&#125;&#125; on Cluster &#123;&#123; . &#125;&#125; &#123;&#123;- end &#125;&#125; has status &#123;&#123; $labels.phase &#125;&#125;. | critical |
| **KubePersistentVolumeFillingUp** | PersistentVolume is filling up. | The PersistentVolume claimed by &#123;&#123; $labels.persistentvolumeclaim &#125;&#125; in Namespace &#123;&#123; $labels.namespace &#125;&#125; &#123;&#123; with $labels.cluster -&#125;&#125; on Cluster &#123;&#123; . &#125;&#125; &#123;&#123;- end &#125;&#125; is only &#123;&#123; $value \| humanizePercentage &#125;&#125; free. | critical |
| **KubePersistentVolumeFillingUp** | PersistentVolume is filling up. | Based on recent sampling, the PersistentVolume claimed by &#123;&#123; $labels.persistentvolumeclaim &#125;&#125; in Namespace &#123;&#123; $labels.namespace &#125;&#125; &#123;&#123; with $labels.cluster -&#125;&#125; on Cluster &#123;&#123; . &#125;&#125; &#123;&#123;- end &#125;&#125; is expected to fill up within four days. Currently &#123;&#123; $value \| humanizePercentage &#125;&#125; is available. | warning |
| **KubePersistentVolumeInodesFillingUp** | PersistentVolumeInodes are filling up. | The PersistentVolume claimed by &#123;&#123; $labels.persistentvolumeclaim &#125;&#125; in Namespace &#123;&#123; $labels.namespace &#125;&#125; &#123;&#123; with $labels.cluster -&#125;&#125; on Cluster &#123;&#123; . &#125;&#125; &#123;&#123;- end &#125;&#125; only has &#123;&#123; $value \| humanizePercentage &#125;&#125; free inodes. | critical |
| **KubePersistentVolumeInodesFillingUp** | PersistentVolumeInodes are filling up. | Based on recent sampling, the PersistentVolume claimed by &#123;&#123; $labels.persistentvolumeclaim &#125;&#125; in Namespace &#123;&#123; $labels.namespace &#125;&#125; &#123;&#123; with $labels.cluster -&#125;&#125; on Cluster &#123;&#123; . &#125;&#125; &#123;&#123;- end &#125;&#125; is expected to run out of inodes within four days. Currently &#123;&#123; $value \| humanizePercentage &#125;&#125; of its inodes are free. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeClientErrors** | Kubernetes API server client is experiencing errors. | Kubernetes API server client '&#123;&#123; $labels.job &#125;&#125;/&#123;&#123; $labels.instance &#125;&#125;' is experiencing &#123;&#123; $value \| humanizePercentage &#125;&#125; errors on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeVersionMismatch** | Different semantic versions of Kubernetes components running. | There are &#123;&#123; $value &#125;&#125; different semantic versions of Kubernetes components running on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system-apiserver
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeAPIDown** | Target disappeared from Prometheus target discovery. | KubeAPI has disappeared from Prometheus target discovery. | critical |
| **KubeAPITerminatedRequests** | The kubernetes apiserver has terminated &#123;&#123; $value \| humanizePercentage &#125;&#125; of its incoming requests. | The kubernetes apiserver has terminated &#123;&#123; $value \| humanizePercentage &#125;&#125; of its incoming requests on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeAggregatedAPIDown** | Kubernetes aggregated API is down. | Kubernetes aggregated API &#123;&#123; $labels.name &#125;&#125;/&#123;&#123; $labels.namespace &#125;&#125; has been only &#123;&#123; $value \| humanize &#125;&#125;% available over the last 10m on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeAggregatedAPIErrors** | Kubernetes aggregated API has reported errors. | Kubernetes aggregated API &#123;&#123; $labels.instance &#125;&#125;/&#123;&#123; $labels.name &#125;&#125; has reported &#123;&#123; $labels.reason &#125;&#125; errors on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeClientCertificateExpiration** | Client certificate is about to expire. | A client certificate used to authenticate to kubernetes apiserver is expiring in less than 7.0 days on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeClientCertificateExpiration** | Client certificate is about to expire. | A client certificate used to authenticate to kubernetes apiserver is expiring in less than 24.0 hours on cluster &#123;&#123; $labels.cluster &#125;&#125;. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system-controller-manager
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeControllerManagerDown** | Target disappeared from Prometheus target discovery. | KubeControllerManager has disappeared from Prometheus target discovery. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system-kube-proxy
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeProxyDown** | Target disappeared from Prometheus target discovery. | KubeProxy has disappeared from Prometheus target discovery. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system-kubelet
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeNodeEviction** | Node is evicting pods. | Node &#123;&#123; $labels.node &#125;&#125; on &#123;&#123; $labels.cluster &#125;&#125; is evicting Pods due to &#123;&#123; $labels.eviction_signal &#125;&#125;.  Eviction occurs when eviction thresholds are crossed, typically caused by Pods exceeding RAM/ephemeral-storage limits. | info |
| **KubeNodeNotReady** | Node is not ready. | &#123;&#123; $labels.node &#125;&#125; has been unready for more than 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeNodePressure** | Node has as active Condition. | &#123;&#123; $labels.node &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125; has active Condition &#123;&#123; $labels.condition &#125;&#125;. This is caused by resource usage exceeding eviction thresholds. | info |
| **KubeNodeReadinessFlapping** | Node readiness status is flapping. | The readiness status of node &#123;&#123; $labels.node &#125;&#125; has changed &#123;&#123; $value &#125;&#125; times in the last 15 minutes on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeNodeUnreachable** | Node is unreachable. | &#123;&#123; $labels.node &#125;&#125; is unreachable and some workloads may be rescheduled on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletClientCertificateExpiration** | Kubelet client certificate is about to expire. | Client certificate for Kubelet on node &#123;&#123; $labels.node &#125;&#125; expires in &#123;&#123; $value \| humanizeDuration &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletClientCertificateExpiration** | Kubelet client certificate is about to expire. | Client certificate for Kubelet on node &#123;&#123; $labels.node &#125;&#125; expires in &#123;&#123; $value \| humanizeDuration &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | critical |
| **KubeletClientCertificateRenewalErrors** | Kubelet has failed to renew its client certificate. | Kubelet on node &#123;&#123; $labels.node &#125;&#125; has failed to renew its client certificate (&#123;&#123; $value \| humanize &#125;&#125; errors in the last 5 minutes) on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletDown** | Target disappeared from Prometheus target discovery. | Kubelet has disappeared from Prometheus target discovery. | critical |
| **KubeletPlegDurationHigh** | Kubelet Pod Lifecycle Event Generator is taking too long to relist. | The Kubelet Pod Lifecycle Event Generator has a 99th percentile duration of &#123;&#123; $value &#125;&#125; seconds on node &#123;&#123; $labels.node &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletPodStartUpLatencyHigh** | Kubelet Pod startup latency is too high. | Kubelet Pod startup 99th percentile latency is &#123;&#123; $value &#125;&#125; seconds on node &#123;&#123; $labels.node &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletServerCertificateExpiration** | Kubelet server certificate is about to expire. | Server certificate for Kubelet on node &#123;&#123; $labels.node &#125;&#125; expires in &#123;&#123; $value \| humanizeDuration &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletServerCertificateExpiration** | Kubelet server certificate is about to expire. | Server certificate for Kubelet on node &#123;&#123; $labels.node &#125;&#125; expires in &#123;&#123; $value \| humanizeDuration &#125;&#125; on cluster &#123;&#123; $labels.cluster &#125;&#125;. | critical |
| **KubeletServerCertificateRenewalErrors** | Kubelet has failed to renew its server certificate. | Kubelet on node &#123;&#123; $labels.node &#125;&#125; has failed to renew its server certificate (&#123;&#123; $value \| humanize &#125;&#125; errors in the last 5 minutes) on cluster &#123;&#123; $labels.cluster &#125;&#125;. | warning |
| **KubeletTooManyPods** | Kubelet is running at capacity. | Kubelet '&#123;&#123; $labels.node &#125;&#125;' is running at &#123;&#123; $value \| humanizePercentage &#125;&#125; of its Pod capacity on cluster &#123;&#123; $labels.cluster &#125;&#125;. | info |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## kubernetes-system-scheduler
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **KubeSchedulerDown** | Target disappeared from Prometheus target discovery. | KubeScheduler has disappeared from Prometheus target discovery. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## mariadb-alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **MariaDBDown** | MariaDB not up and running, immediate attention is required. | MariaDB &#123;&#123;$labels.job&#125;&#125; on &#123;&#123;$labels.instance&#125;&#125; is not up. | critical |
| **MariaDBReplicationErrors** | MariaDB is reporting replication errors from &#123;&#123;$labels.instance&#125;&#125;, immediate attention is required. | MariaDB &#123;&#123;$labels.job&#125;&#125; on &#123;&#123;$labels.instance&#125;&#125; is reporting replication errors. | critical |
| **MysqlSlaveReplicationLag** | MySQL Slave replication lag (instance &#123;&#123; $labels.instance &#125;&#125;) | MySQL replication lag on &#123;&#123; $labels.instance &#125;&#125;<br>  VALUE = &#123;&#123; $value &#125;&#125;<br>  LABELS = &#123;&#123; $labels &#125;&#125; | critical |
| **MysqlTooManyConnections(>80%)** | MySQL too many connections (> 80%) (instance &#123;&#123; $labels.instance &#125;&#125;) | More than 80% of MySQL connections are in use on &#123;&#123; $labels.instance &#125;&#125;<br>  VALUE = &#123;&#123; $value &#125;&#125;<br>  LABELS = &#123;&#123; $labels &#125;&#125; | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## node-exporter
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **NodeBondingDegraded** | Bonding interface is degraded | Bonding interface &#123;&#123; $labels.master &#125;&#125; on &#123;&#123; $labels.instance &#125;&#125; is in degraded state due to one or more slave failures. | warning |
| **NodeCPUHighUsage** | High CPU usage. | CPU usage at &#123;&#123; $labels.instance &#125;&#125; has been above 90% for the last 15 minutes, is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;%.<br> | info |
| **NodeClockNotSynchronising** | Clock not synchronising. | Clock at &#123;&#123; $labels.instance &#125;&#125; is not synchronising. Ensure NTP is configured on this host. | warning |
| **NodeClockSkewDetected** | Clock skew detected. | Clock at &#123;&#123; $labels.instance &#125;&#125; is out of sync by more than 0.05s. Ensure NTP is configured correctly on this host. | warning |
| **NodeDiskIOSaturation** | Disk IO queue is high. | Disk IO queue (aqu-sq) is high on &#123;&#123; $labels.device &#125;&#125; at &#123;&#123; $labels.instance &#125;&#125;, has been above 10 for the last 30 minutes, is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;.<br>This symptom might indicate disk saturation.<br> | warning |
| **NodeFileDescriptorLimit** | Kernel is predicted to exhaust file descriptors limit soon. | File descriptors limit at &#123;&#123; $labels.instance &#125;&#125; is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;%. | warning |
| **NodeFileDescriptorLimit** | Kernel is predicted to exhaust file descriptors limit soon. | File descriptors limit at &#123;&#123; $labels.instance &#125;&#125; is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;%. | critical |
| **NodeFilesystemAlmostOutOfFiles** | Filesystem has less than 5% inodes left. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available inodes left. | warning |
| **NodeFilesystemAlmostOutOfFiles** | Filesystem has less than 3% inodes left. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available inodes left. | critical |
| **NodeFilesystemAlmostOutOfSpace** | Filesystem has less than 5% space left. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available space left. | warning |
| **NodeFilesystemAlmostOutOfSpace** | Filesystem has less than 3% space left. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available space left. | critical |
| **NodeFilesystemFilesFillingUp** | Filesystem is predicted to run out of inodes within the next 24 hours. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available inodes left and is filling up. | warning |
| **NodeFilesystemFilesFillingUp** | Filesystem is predicted to run out of inodes within the next 4 hours. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available inodes left and is filling up fast. | critical |
| **NodeFilesystemSpaceFillingUp** | Filesystem is predicted to run out of space within the next 24 hours. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available space left and is filling up. | warning |
| **NodeFilesystemSpaceFillingUp** | Filesystem is predicted to run out of space within the next 4 hours. | Filesystem on &#123;&#123; $labels.device &#125;&#125;, mounted on &#123;&#123; $labels.mountpoint &#125;&#125;, at &#123;&#123; $labels.instance &#125;&#125; has only &#123;&#123; printf "%.2f" $value &#125;&#125;% available space left and is filling up fast. | critical |
| **NodeHighNumberConntrackEntriesUsed** | Number of conntrack are getting close to the limit. | &#123;&#123; $labels.instance &#125;&#125; &#123;&#123; $value \| humanizePercentage &#125;&#125; of conntrack entries are used. | warning |
| **NodeMemoryHighUtilization** | Host is running out of memory. | Memory is filling up at &#123;&#123; $labels.instance &#125;&#125;, has been above 90% for the last 15 minutes, is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;%.<br> | warning |
| **NodeMemoryMajorPagesFaults** | Memory major page faults are occurring at very high rate. | Memory major pages are occurring at very high rate at &#123;&#123; $labels.instance &#125;&#125;, 500 major page faults per second for the last 15 minutes, is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;.<br>Please check that there is enough memory available at this instance.<br> | warning |
| **NodeNetworkReceiveErrs** | Network interface is reporting many receive errors. | &#123;&#123; $labels.instance &#125;&#125; interface &#123;&#123; $labels.device &#125;&#125; has encountered &#123;&#123; printf "%.0f" $value &#125;&#125; receive errors in the last two minutes. | warning |
| **NodeNetworkTransmitErrs** | Network interface is reporting many transmit errors. | &#123;&#123; $labels.instance &#125;&#125; interface &#123;&#123; $labels.device &#125;&#125; has encountered &#123;&#123; printf "%.0f" $value &#125;&#125; transmit errors in the last two minutes. | warning |
| **NodeRAIDDegraded** | RAID Array is degraded. | RAID array '&#123;&#123; $labels.device &#125;&#125;' at &#123;&#123; $labels.instance &#125;&#125; is in degraded state due to one or more disks failures. Number of spare drives is insufficient to fix issue automatically. | critical |
| **NodeRAIDDiskFailure** | Failed device in RAID array. | At least one device in RAID array at &#123;&#123; $labels.instance &#125;&#125; failed. Array '&#123;&#123; $labels.device &#125;&#125;' needs attention and possibly a disk swap. | warning |
| **NodeSystemSaturation** | System saturated, load per core is very high. | System load per core at &#123;&#123; $labels.instance &#125;&#125; has been above 2 for the last 15 minutes, is currently at &#123;&#123; printf "%.2f" $value &#125;&#125;.<br>This might indicate this instance resources saturation and can cause it becoming unresponsive.<br> | warning |
| **NodeSystemdServiceCrashlooping** | Systemd service keeps restaring, possibly crash looping. | Systemd service &#123;&#123; $labels.name &#125;&#125; has being restarted too many times at &#123;&#123; $labels.instance &#125;&#125; for the last 15 minutes. Please check if service is crash looping. | warning |
| **NodeSystemdServiceFailed** | Systemd service has entered failed state. | Systemd service &#123;&#123; $labels.name &#125;&#125; has entered failed state at &#123;&#123; $labels.instance &#125;&#125; | warning |
| **NodeTextFileCollectorScrapeError** | Node Exporter text file collector failed to scrape. | Node Exporter text file collector on &#123;&#123; $labels.instance &#125;&#125; failed to scrape. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## node-network
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **NodeNetworkInterfaceFlapping** | Network interface is often changing its status | Network interface "&#123;&#123; $labels.device &#125;&#125;" changing its up status often on node-exporter &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod &#125;&#125; | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## pod-state-alerts
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **HighPodRestartRate** | High pod restart count detected | Pod &#123;&#123; $labels.pod &#125;&#125; in namespace &#123;&#123; $labels.namespace &#125;&#125; is restarting frequently, which may indicate network instability. | warning |
| **KubePodNotReadyCritical** | Pod has been in a non-ready state for more than 5 minutes. | Pod &#123;&#123; $labels.namespace &#125;&#125;/&#123;&#123; $labels.pod &#125;&#125; has been in a non-ready state for longer than 5 minutes. | critical |
| **TooManyContainerRestarts** | Container named &#123;&#123; $labels.container &#125;&#125; in &#123;&#123; $labels.pod &#125;&#125; in &#123;&#123; $labels.namespace &#125;&#125; has restarted too many times in a short period and needs to be investigated. | Namespace: &#123;&#123;$labels.namespace&#125;&#125;<br>Pod name: &#123;&#123;$labels.pod&#125;&#125;<br>Container name: &#123;&#123;$labels.container&#125;&#125;<br> | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## prometheus
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **PrometheusBadConfig** | Failed Prometheus configuration reload. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has failed to reload its configuration. | critical |
| **PrometheusDuplicateTimestamps** | Prometheus is dropping samples with duplicate timestamps. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is dropping &#123;&#123; printf "%.4g" $value  &#125;&#125; samples/s with different values but duplicated timestamp. | warning |
| **PrometheusErrorSendingAlertsToAnyAlertmanager** | Prometheus encounters more than 3% errors sending alerts to any Alertmanager. | &#123;&#123; printf "%.1f" $value &#125;&#125;% minimum errors while sending alerts from Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; to any Alertmanager. | critical |
| **PrometheusErrorSendingAlertsToSomeAlertmanagers** | More than 1% of alerts sent by Prometheus to a specific Alertmanager were affected by errors. | &#123;&#123; printf "%.1f" $value &#125;&#125;% of alerts sent by Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; to Alertmanager &#123;&#123;$labels.alertmanager&#125;&#125; were affected by errors. | warning |
| **PrometheusHighQueryLoad** | Prometheus is reaching its maximum capacity serving concurrent requests. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; query API has less than 20% available capacity in its query engine for the last 15 minutes. | warning |
| **PrometheusKubernetesListWatchFailures** | Requests in Kubernetes SD are failing. | Kubernetes service discovery of Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is experiencing &#123;&#123; printf "%.0f" $value &#125;&#125; failures with LIST/WATCH requests to the Kubernetes API in the last 5 minutes. | warning |
| **PrometheusLabelLimitHit** | Prometheus has dropped targets because some scrape configs have exceeded the labels limit. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has dropped &#123;&#123; printf "%.0f" $value &#125;&#125; targets because some samples exceeded the configured label_limit, label_name_length_limit or label_value_length_limit. | warning |
| **PrometheusMissingRuleEvaluations** | Prometheus is missing rule evaluations due to slow rule group evaluation. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has missed &#123;&#123; printf "%.0f" $value &#125;&#125; rule group evaluations in the last 5m. | warning |
| **PrometheusNotConnectedToAlertmanagers** | Prometheus is not connected to any Alertmanagers. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is not connected to any Alertmanagers. | warning |
| **PrometheusNotIngestingSamples** | Prometheus is not ingesting samples. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is not ingesting samples. | warning |
| **PrometheusNotificationQueueRunningFull** | Prometheus alert notification queue predicted to run full in less than 30m. | Alert notification queue of Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is running full. | warning |
| **PrometheusOutOfOrderTimestamps** | Prometheus drops samples with out-of-order timestamps. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; is dropping &#123;&#123; printf "%.4g" $value  &#125;&#125; samples/s with timestamps arriving out of order. | warning |
| **PrometheusRemoteStorageFailures** | Prometheus fails to send samples to remote storage. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; failed to send &#123;&#123; printf "%.1f" $value &#125;&#125;% of the samples to &#123;&#123; $labels.remote_name&#125;&#125;:&#123;&#123; $labels.url &#125;&#125; | critical |
| **PrometheusRemoteWriteBehind** | Prometheus remote write is behind. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; remote write is &#123;&#123; printf "%.1f" $value &#125;&#125;s behind for &#123;&#123; $labels.remote_name&#125;&#125;:&#123;&#123; $labels.url &#125;&#125;. | critical |
| **PrometheusRemoteWriteDesiredShards** | Prometheus remote write desired shards calculation wants to run more than configured max shards. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; remote write desired shards calculation wants to run &#123;&#123; $value &#125;&#125; shards for queue &#123;&#123; $labels.remote_name&#125;&#125;:&#123;&#123; $labels.url &#125;&#125;, which is more than the max of &#123;&#123; printf `prometheus_remote_storage_shards_max{instance="%s",job="kube-prometheus-stack-prometheus",namespace="prometheus"}` $labels.instance \| query \| first \| value &#125;&#125;. | warning |
| **PrometheusRuleFailures** | Prometheus is failing rule evaluations. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has failed to evaluate &#123;&#123; printf "%.0f" $value &#125;&#125; rules in the last 5m. | critical |
| **PrometheusSDRefreshFailure** | Failed Prometheus SD refresh. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has failed to refresh SD with mechanism &#123;&#123;$labels.mechanism&#125;&#125;. | warning |
| **PrometheusScrapeBodySizeLimitHit** | Prometheus has dropped some targets that exceeded body size limit. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has failed &#123;&#123; printf "%.0f" $value &#125;&#125; scrapes in the last 5m because some targets exceeded the configured body_size_limit. | warning |
| **PrometheusScrapeSampleLimitHit** | Prometheus has failed scrapes that have exceeded the configured sample limit. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has failed &#123;&#123; printf "%.0f" $value &#125;&#125; scrapes in the last 5m because some targets exceeded the configured sample_limit. | warning |
| **PrometheusTSDBCompactionsFailing** | Prometheus has issues compacting blocks. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has detected &#123;&#123;$value \| humanize&#125;&#125; compaction failures over the last 3h. | warning |
| **PrometheusTSDBReloadsFailing** | Prometheus has issues reloading blocks from disk. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has detected &#123;&#123;$value \| humanize&#125;&#125; reload failures over the last 3h. | warning |
| **PrometheusTargetLimitHit** | Prometheus has dropped targets because some scrape configs have exceeded the targets limit. | Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; has dropped &#123;&#123; printf "%.0f" $value &#125;&#125; targets because the number of targets exceeded the configured target_limit. | warning |
| **PrometheusTargetSyncFailure** | Prometheus has failed to sync targets. | &#123;&#123; printf "%.0f" $value &#125;&#125; targets in Prometheus &#123;&#123;$labels.namespace&#125;&#125;/&#123;&#123;$labels.pod&#125;&#125; have failed to sync because invalid configuration was supplied. | critical |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## prometheus-operator
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **PrometheusOperatorListErrors** | Errors while performing list operations in controller. | Errors while performing List operations in controller &#123;&#123;$labels.controller&#125;&#125; in &#123;&#123;$labels.namespace&#125;&#125; namespace. | warning |
| **PrometheusOperatorNodeLookupErrors** | Errors while reconciling Prometheus. | Errors while reconciling Prometheus in &#123;&#123; $labels.namespace &#125;&#125; Namespace. | warning |
| **PrometheusOperatorNotReady** | Prometheus operator not ready | Prometheus operator in &#123;&#123; $labels.namespace &#125;&#125; namespace isn't ready to reconcile &#123;&#123; $labels.controller &#125;&#125; resources. | warning |
| **PrometheusOperatorReconcileErrors** | Errors while reconciling objects. | &#123;&#123; $value \| humanizePercentage &#125;&#125; of reconciling operations failed for &#123;&#123; $labels.controller &#125;&#125; controller in &#123;&#123; $labels.namespace &#125;&#125; namespace. | warning |
| **PrometheusOperatorRejectedResources** | Resources rejected by Prometheus operator | Prometheus operator in &#123;&#123; $labels.namespace &#125;&#125; namespace rejected &#123;&#123; printf "%0.0f" $value &#125;&#125; &#123;&#123; $labels.controller &#125;&#125;/&#123;&#123; $labels.resource &#125;&#125; resources. | warning |
| **PrometheusOperatorStatusUpdateErrors** | Errors while updating objects status. | &#123;&#123; $value \| humanizePercentage &#125;&#125; of status update operations failed for &#123;&#123; $labels.controller &#125;&#125; controller in &#123;&#123; $labels.namespace &#125;&#125; namespace. | warning |
| **PrometheusOperatorSyncFailed** | Last controller reconciliation failed | Controller &#123;&#123; $labels.controller &#125;&#125; in &#123;&#123; $labels.namespace &#125;&#125; namespace fails to reconcile &#123;&#123; $value &#125;&#125; objects. | warning |
| **PrometheusOperatorWatchErrors** | Errors while performing watch operations in controller. | Errors while performing watch operations in controller &#123;&#123;$labels.controller&#125;&#125; in &#123;&#123;$labels.namespace&#125;&#125; namespace. | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

## rabbitmq
| Alert Name | Summary | Description | Severity |
| :--- | :--- | :--- | :--- |
| **ContainerRestarts** | Investigate why the container got restarted.<br>Check the logs of the current container: `kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }}`<br>Check the logs of the previous container: `kubectl -n {{ $labels.namespace }} logs {{ $labels.pod }} --previous`<br>Check the last state of the container: `kubectl -n {{ $labels.namespace }} get pod {{ $labels.pod }} -o jsonpath='{.status.containerStatuses[].lastState}'`<br> | Over the last 10 minutes, container `{{ $labels.container }}`<br>restarted `{{ $value \| printf "%.0f" }}` times in pod `{{ $labels.pod }}` of RabbitMQ cluster<br>`{{ $labels.rabbitmq_cluster }}` in namespace `{{ $labels.namespace }}`.<br> | warning |
| **FileDescriptorsNearLimit** | More than 80% of file descriptors are used on the RabbitMQ node.<br>When this value reaches 100%, new connections will not be accepted and disk write operations may fail.<br>Client libraries, peer nodes and CLI tools will not be able to connect when the node runs out of available file descriptors.<br>See https://www.rabbitmq.com/production-checklist.html#resource-limits-file-handle-limit.<br> | `{{ $value \| humanizePercentage }}` file descriptors of file<br>descriptor limit are used in RabbitMQ node `{{ $labels.rabbitmq_node }}`,<br>pod `{{ $labels.pod }}`, RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}`,<br>namespace `{{ $labels.namespace }}`.<br> | warning |
| **HighConnectionChurn** | More than 10% of total connections are churning.<br>This means that client application connections are short-lived instead of long-lived.<br>Read https://www.rabbitmq.com/connections.html#high-connection-churn to understand why this is an anti-pattern.<br> | Over the last 5 minutes, `{{ $value \| humanizePercentage }}`<br>of total connections are closed or opened per second in RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}`<br>in namespace `{{ $labels.namespace }}`.<br> | warning |
| **InsufficientEstablishedErlangDistributionLinks** | RabbitMQ clusters have a full mesh topology.<br>All RabbitMQ nodes connect to all other RabbitMQ nodes in both directions.<br>The expected number of established Erlang distribution links is therefore `n*(n-1)` where `n` is the number of RabbitMQ nodes in the cluster.<br>Therefore, the expected number of distribution links are `0` for a 1-node cluster, `6` for a 3-node cluster, and `20` for a 5-node cluster.<br>This alert reports that the number of established distributions links is less than the expected number.<br>Some reasons for this alert include failed network links, network partitions, failed clustering (i.e. nodes can't join the cluster).<br>Check the panels `All distribution links`, `Established distribution links`, `Connecting distributions links`, `Waiting distribution links`, and `distribution links`<br>of the Grafana dashboard `Erlang-Distribution`.<br>Check the logs of the RabbitMQ nodes: `kubectl -n {{ $labels.namespace }} logs -l app.kubernetes.io/component=rabbitmq,app.kubernetes.io/name={{ $labels.rabbitmq_cluster }}`<br> | There are only `{{ $value }}` established Erlang distribution links<br>in RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` in namespace `{{ $labels.namespace }}`.<br> | warning |
| **LowDiskWatermarkPredicted** | Based on the trend of available disk space over the past 24 hours, it's predicted that, in 24 hours from now, a disk alarm will be triggered since the free disk space will drop below the free disk space limit.<br>This alert is reported for the partition where the RabbitMQ data directory is stored.<br>When the disk alarm will be triggered, all publishing connections across all cluster nodes will be blocked.<br>See<br>https://www.rabbitmq.com/alarms.html,<br>https://www.rabbitmq.com/disk-alarms.html,<br>https://www.rabbitmq.com/production-checklist.html#resource-limits-disk-space,<br>https://www.rabbitmq.com/persistence-conf.html,<br>https://www.rabbitmq.com/connection-blocked.html.<br> | The predicted free disk space in 24 hours from now is `{{ $value \| humanize1024 }}B`<br>in RabbitMQ node `{{ $labels.rabbitmq_node }}`, pod `{{ $labels.pod }}`,<br>RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}`, namespace `{{ $labels.namespace }}`.<br> | warning |
| **MemoryAlarm** | A RabbitMQ node reached the `vm_memory_high_watermark` threshold.<br>See https://www.rabbitmq.com/docs/alarms#overview, https://www.rabbitmq.com/docs/memory.<br> | RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` memory alarm active. Publishers are blocked.<br> | warning |
| **NoMajorityOfNodesReady** | No majority of nodes have been ready for the last 5 minutes.<br>Check the details of the pods:<br>`kubectl -n {{ $labels.namespace }} describe pods -l app.kubernetes.io/component=rabbitmq,app.kubernetes.io/name={{ $labels.label_app_kubernetes_io_name }}`<br> | Only `{{ $value }}` replicas are ready in StatefulSet `{{ $labels.statefulset }}`<br>of RabbitMQ cluster `{{ $labels.label_app_kubernetes_io_name }}` in namespace `{{ $labels.namespace }}`.<br> | warning |
| **PersistentVolumeMissing** | RabbitMQ needs a PersistentVolume for its data.<br>However, there is no PersistentVolume bound to the PersistentVolumeClaim.<br>This means the requested storage could not be provisioned.<br>Check the status of the PersistentVolumeClaim: `kubectl -n {{ $labels.namespace }} describe pvc {{ $labels.persistentvolumeclaim }}`.<br> | PersistentVolumeClaim `{{ $labels.persistentvolumeclaim }}` of<br>RabbitMQ cluster `{{ $labels.label_app_kubernetes_io_name }}` in namespace<br>`{{ $labels.namespace }}` is not bound.<br> | critical |
| **QueueHasNoConsumers** | Messages are sitting idle in the queue, without any processing.<br>This alert is highly application specific (and e.g. doesn't make sense for stream queues).<br> | Over the last 10 minutes, non-empty queue `{{ $labels.queue }}` with &#123;&#123; $value &#125;&#125; messages<br>in virtual host `{{ $labels.vhost }}` didn't have any consumers in<br>RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` in namespace `{{ $labels.namespace }}`.<br> | warning |
| **QueueIsGrowing** | Queue size is steadily growing over time.<br> | Over the last 10 minutes, queue `{{ $labels.queue }}` in virtual host `{{ $labels.vhost }}`<br>was growing. 10 minute moving average has grown by &#123;&#123; $value &#125;&#125;.<br>This happens in RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` in namespace `{{ $labels.namespace }}`.<br> | warning |
| **RabbitmqDiskAlarm** | A RabbitMQ node reached the `disk_free_limit` threshold.<br>See https://www.rabbitmq.com/docs/alarms#overview, https://www.rabbitmq.com/docs/disk-alarms.<br> | RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` disk alarm active. Publishers are blocked.<br> | warning |
| **RabbitmqFileDescriptorAlarm** | A RabbitMQ node ran out of file descriptors.<br>See https://www.rabbitmq.com/docs/alarms#file-descriptors.<br> | RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` file descriptor alarm active. Publishers are blocked.<br> | warning |
| **TCPSocketsNearLimit** | More than 80% of TCP sockets are open on the RabbitMQ node.<br>When this value reaches 100%, new connections will not be accepted.<br>Client libraries, peer nodes and CLI tools will not be able to connect when the node runs out of available TCP sockets.<br>See https://www.rabbitmq.com/networking.html.<br> | `{{ $value \| humanizePercentage }}` TCP sockets of TCP socket<br>limit are open in RabbitMQ node `{{ $labels.rabbitmq_node }}`, pod `{{ $labels.pod }}`,<br>RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}`, namespace `{{ $labels.namespace }}`.<br> | warning |
| **UnroutableMessages** | There are messages published into an exchange which cannot be routed and are either dropped silently, or returned to publishers.<br>Is your routing topology set up correctly?<br>Check your application code and bindings between exchanges and queues.<br>See<br>https://www.rabbitmq.com/publishers.html#unroutable,<br>https://www.rabbitmq.com/confirms.html#when-publishes-are-confirmed.<br> | There were `{{ $value \| printf "%.0f" }}` unroutable messages within the last<br>5 minutes in RabbitMQ cluster `{{ $labels.rabbitmq_cluster }}` in namespace<br>`{{ $labels.namespace }}`.<br> | warning |
<p align="right"><a href="#top">🔝 Back to Top</a></p>

---

