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

!!! tip "Column Statistics"

    With some versions of `mysqldump` the `--column-statistics=0` flag maybe be required. If required the following error will be thrown:

    ``` sql
    Unknown table 'COLUMN_STATISTICS' in information_schema (1109)
    ```

### All Databases Backup

Run the `/opt/genestack/bin/backup-mariadb.sh` script to dump all databases as individual files in `~/backup/mariadb/$(date +%s)`.

??? example "Database Backup Script: `/opt/genestack/bin/backup-mariadb.sh`"

    ``` shell
    --8<-- "bin/backup-mariadb.sh"
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

## Fixing Replication

The MariaDB Operator can handle most cluster issues automatically, but
sometimes you’ll need to roll up your sleeves and step in to fix things.
This guide walks you through repairing replication on a broken slave
to keep your deployment up and running.

In this example, mariadb-cluster-0 is the broken slave, and we’ll use
a backup from the current primary, mariadb-cluster-1, to kickstart
replication again on the busted pod.


### Prepare and Restore Backup

1. Take a full backup of the primary: mariadb-cluster-1

    ``` shell
    mariadb-dump --all-databases --master-data=2 --single-transaction --flush-logs -u root -p$MARIADB_ROOT_PASSWORD > /tmp/mariadb-cluster-1.sql
    ```

2. Copy the backup off of the pod, onto your machine

    ``` shell
    kubectl -n openstack cp mariadb-cluster-1:/tmp/mariadb-cluster-1.sql /home/ubuntu/backups/mariadb-cluster-1.sql
    ```

3. Copy the backup to the broken slave, mariadb-cluster-0

    ``` shell
    kubectl -n openstack cp /home/ubuntu/backups/mariadb-cluster-1.sql mariadb-cluster-0:/tmp/mariadb-cluster-1.sql
    ```

4. Restore the backup, depending on its contents it may take a while, be 
   patient.

    ``` shell
    mariadb -u root -p$MARIADB_ROOT_PASSWORD < /tmp/mariadb-cluster-1.sql
    ```

### Stop and Reset the Slave

Execute on the broken slave pod, mariadb-cluster-0:

``` shell
STOP SLAVE; RESET SLAVE ALL; STOP SLAVE 'mariadb-operator'; RESET SLAVE 'mariadb-operator' ALL;
```

### Find Master Log and Position

Identify master log file and position from the backup file:

``` shell
[SJC3] ubuntu@bastion:~/backups$ grep "CHANGE MASTER TO MASTER_LOG_FILE='mariadb-cluster-bin." mariadb-cluster-1.sql
-- CHANGE MASTER TO MASTER_LOG_FILE='mariadb-cluster-bin.000206', MASTER_LOG_POS=405;
```

###  Update and Restart Slave

1. Change the values in the following command to include the master log file 
   and position from your previous grep result, making sure to also replace the 
   master password value with the one from your cluster along with the real 
   MASTER_HOST from your environment, then execute it on the broken slave 
   pod (in our example, that is mariadb-cluster-0).

    ``` shell
    CHANGE MASTER TO MASTER_HOST='mariadb-cluster-1.mariadb-cluster-internal.openstack.svc.cluster.local', MASTER_USER='repl', MASTER_PASSWORD='<FIND ME IN K8s secret repl-password-mariadb-cluster>', MASTER_LOG_FILE='mariadb-cluster-bin.000206', MASTER_LOG_POS=405;
    ```

    !!! tip "If `CHANGE MASTER` fails..."

        If the previous command to CHANGE MASTER fails, one may need to
        `FLUSH PRIVILEGES;` first.

2. Start the slave process again

    ``` shell
    START SLAVE;
    ```

3. Verify replication status is OK

    ``` shell
    SHOW ALL REPLICAS STATUS\G
    ```

4. Wait for replication to be caught up, then kill the slave pod. We are 
   doing this to ensure it comes back online as expected (the operator should 
   automatically execute CHANGE MASTER for mariadb-operator on the slave). 
   When the pod has started; logs should contain something like the following:

    ``` text
    2025-01-28 22:22:55 61 [Note] Master connection name: 'mariadb-operator'  Master_info_file: 'master-mariadb@002doperator.info'  Relay_info_file: 'relay-log-mariadb@002doperator.info'
    2025-01-28 22:22:55 61 [Note] 'CHANGE MASTER TO executed'. Previous state master_host='', master_port='3306', master_log_file='', master_log_pos='4'. New state master_host='mariadb-cluster-1.mariadb-cluster-internal.openstack.svc.cluster.local', master_port='3306', master_log_file='', master_log_pos='4'.
    2025-01-28 22:22:55 61 [Note] Previous Using_Gtid=Slave_Pos. New Using_Gtid=Current_Pos
    2025-01-28 22:22:55 63 [Note] Master 'mariadb-operator': Slave I/O thread: Start semi-sync replication to master 'repl@mariadb-cluster-1.mariadb-cluster-internal.openstack.svc.cluster.local:3306' in log '' at position 4
    2025-01-28 22:22:55 64 [Note] Master 'mariadb-operator': Slave SQL thread initialized, starting replication in log 'FIRST' at position 4, relay log './mariadb-cluster-relay-bin-mariadb@002doperator.000001' position: 4; GTID position '0-11-638858622'
    2025-01-28 22:22:55 63 [Note] Master 'mariadb-operator': Slave I/O thread: connected to master 'repl@mariadb-cluster-1.mariadb-cluster-internal.openstack.svc.cluster.local:3306',replication starts at GTID position '0-11-638858622'
    ```
