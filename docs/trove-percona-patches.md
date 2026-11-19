# Trove Percona patches

These patches support Percona Server for MySQL 8.4 on Trove `stable/2026.1`. The `.patch` files are clean unified-diff artifacts; each change is applied by the workflow that builds or configures its target component.

## Guest-agent configuration

`percona_guestagent_cfg_py_docker_image.patch` adds the missing `docker_image` and `backup_docker_image` options to Trove's `percona` configuration group. Without these options, the guest agent raises `NoSuchOptError` while starting the Percona container. The equivalent change is applied by the DIB pre-install hook before the guest agent is installed into the QCOW2 image. The patch keeps the Percona and MySQL configuration groups independent. It targets the Trove `stable/2026.1` guest-agent source.


## Configuration validation rules

`percona_taskmanager_validation_rules_8_4.patch` replaces Trove's incomplete Percona validation rules with the Percona Server 8.4 configuration surface. The expanded rules include MySQL-compatible settings and Percona-specific features such as thread pooling, audit logging, and enhanced statistics. The resulting JSON is staged into the taskmanager pod and loaded with `trove-manage`. The unified diff remains as a reviewable source artifact rather than being applied directly to the read-only package directory. It targets `trove/templates/percona/validation-rules.json` on `stable/2026.1`.
