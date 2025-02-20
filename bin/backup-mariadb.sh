#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086

# The script is used to backup the mariadb database in the openstack namespace
# The script will create a backup directory in the HOME directory with the current timestamp
# The script will dump all the databases except the performance_schema and information_schema
# The script will use the root password from the mariadb secret to connect to the database
# The script will use the clusterIP of the mariadb-cluster service to connect to the database
# The script will use the --column-statistics=0 option if available in the mysqldump command
# The script will create a separate dump file for each database

set -e
set -o pipefail

BACKUP_DIR="${HOME}/backup/mariadb/$(date +%s)"
MYSQL_PASSWORD="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
MYSQL_HOST=$(kubectl -n openstack get service mariadb-cluster -o jsonpath='{.spec.clusterIP}')

if mysqldump --help | grep -q column-statistics; then
    MYSQL_DUMP_COLLUMN_STATISTICS="--column-statistics=0"
else
    MYSQL_DUMP_COLLUMN_STATISTICS=""
fi

mkdir -p "${BACKUP_DIR}"

pushd "${BACKUP_DIR}"
    mysql -h ${MYSQL_HOST} \
        -u root \
        -p${MYSQL_PASSWORD} \
        -e 'show databases;' \
        --column-names=false \
        --vertical | \
            awk '/[:alnum:]/ && ! /performance_schema/ && ! /information_schema/' | \
                xargs -i mysqldump --host=${MYSQL_HOST} ${MYSQL_DUMP_COLLUMN_STATISTICS} \
                                    --user=root \
                                    --password=${MYSQL_PASSWORD} \
                                    --single-transaction \
                                    --routines \
                                    --triggers \
                                    --events \
                                    --result-file={} \
                                    {}
popd

echo -e "backup complete and available at ${BACKUP_DIR}"
