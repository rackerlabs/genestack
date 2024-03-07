# Connect to the database

Sometimes an operator may need to connect to the database to troubleshoot things or otherwise make modifications to the databases in place. The following command can be used to connect to the database from a node within the cluster.

``` shell
mysql -h $(kubectl -n openstack get service mariadb-galera-primary -o jsonpath='{.spec.clusterIP}') \
      -p$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d) \
      -u root
```

!!! info

    The following command will leverage your kube configuration and dynamically source the needed information to connect to the MySQL cluster. You will need to ensure you have installed the mysql client tools on the system you're attempting to connect from.
