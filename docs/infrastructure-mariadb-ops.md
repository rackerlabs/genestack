# MariaDB Operations

Tips and tricks for managing and operating the MariaDB cluster within a Genestack environment.

## Connect to the database

Sometimes an operator may need to connect to the database to troubleshoot things or otherwise make modifications to the databases in place. The following command can be used to connect to the database from a node within the cluster.

``` shell
mysql -h $(kubectl -n openstack get service mariadb-cluster-primary -o jsonpath='{.spec.clusterIP}') \
      -p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
      -u root
```

!!! info

    The following command will leverage your kube configuration and dynamically source the needed information to connect to the MySQL cluster. You will need to ensure you have installed the mysql client tools on the system you're attempting to connect from.

## Manually dumping and restoring databases

When running `mysqldump` or `mariadbdump` the following commands can be useful for generating a quick backup.

### Individual Database Backups

``` shell
mysqldump --host=$(kubectl -n openstack get service mariadb-cluster -o jsonpath='{.spec.clusterIP}')\
          --user=root \
          --password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
          --single-transaction \
          --routines \
          --triggers \
          --events \
          --column-statistics=0 \
          ${DATABASE_NAME} \
          --result-file=/tmp/${DATABASE_NAME}-$(date +%s).sql
```

!!! example "Dump all databases as individual files in `/tmp`"

    ``` shell
    mysql -h $(kubectl -n openstack get service mariadb-cluster -o jsonpath='{.spec.clusterIP}') \
          -u root \
          -p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
          -e 'show databases;' \
          --column-names=false \
          --column-statistics=0 \
          --vertical | \
              awk '/[:alnum:]/' | \
                  xargs -i mysqldump --host=$(kubectl -n openstack get service mariadb-cluster -o jsonpath='{.spec.clusterIP}') \
                  --user=root \
                  --password=$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
                  --single-transaction \
                  --routines \
                  --triggers \
                  --events \
                  {} \
                  --result-file=/tmp/{}-$(date +%s).sql
    ```

### Individual Database Restores

!!! tip "Ensure the destination database exists"

    The destination database must exist prior to restoring individual SQL
    backups. If it does not already exist, it's important to create the
    database with the correct charset and collate values. Failing to do so can
    result in errors such as `Foreign Key Constraint is Incorrectly Formed`
    during DB upgrades.

    ```
    CREATE DATABASE ${DATABASE_NAME} DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;
    ```

!!! example "Restoring a database"

    ``` shell
    mysql -h $(kubectl -n openstack get service mariadb-cluster-primary -o jsonpath='{.spec.clusterIP}') \
        -u root \
        -p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
        ${DATABASE_NAME} < /tmp/${DATABASE_FILE}
    ```

## Restore using the MariaDB CRD

To restore the most recent successful backup, create the following resource
to spawn a job that will mount the same storage as the backup and apply the
dump to your MariaDB database.

Refer to the mariadb-operator [restore documentation](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/BACKUP.md#restore)
for more information.

!!! tip "Operator Restore Tips"

    1. If you have multiple backups available, the operator is able to infer
    which backup to restore based on the `spec.targetRecoveryTime` field
    discussed in the operator documentation [here](https://github.com/mariadb-operator/mariadb-operator/blob/main/docs/BACKUP.md#target-recovery-time).
    2. The referred database (db1 in the example below) must previously exist
    for the Restore to succeed.
    3. The mariadb CLI invoked by the operator under the hood only supports
    selecting a single database to restore via the `--one-database` option,
    restoration of multiple specific databases is not supported.

### Restore All Databases

!!! danger "The following command may lead to data loss"

    ``` shell
    cat <<EOF | kubectl -n openstack apply -f -
    apiVersion: k8s.mariadb.com/v1alpha1
    kind: Restore
    metadata:
      name: maria-restore
    spec:
      mariaDbRef:
        name: mariadb-cluster
      backupRef:
        name: mariadb-backup
    EOF
    ```

### Restore Single Database

!!! danger "The following command may lead to data loss"

    ``` shell
    cat <<EOF | kubectl -n openstack apply -f -
    apiVersion: k8s.mariadb.com/v1alpha1
    kind: Restore
    metadata:
      name: maria-restore
    spec:
      mariaDbRef:
        name: mariadb-cluster
      backupRef:
        name: mariadb-backup
      databases: db1
    EOF
    ```

### Check Restore Progress

!!! success "Simply _get_ the restore object previously created"

    ``` shell
    kubectl -n openstack get restore maria-restore
    ```

    ``` { .no-copy }
    NAME            COMPLETE   STATUS    MARIADB           AGE
    maria-restore   True       Success   mariadb-cluster   26s
    ```
