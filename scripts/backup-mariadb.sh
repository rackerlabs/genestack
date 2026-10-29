# -----------------------------------------------
#                             _             _
#                            | |           | |
#   __ _  ___ _ __   ___  ___| |_ __ _  ___| | __
#  / _` |/ _ \ '_ \ / _ \/ __| __/ _` |/ __| |/ /
# | (_| |  __/ | | |  __/\__ \ || (_| | (__|   <
#  \__, |\___|_| |_|\___||___/\__\__,_|\___|_|\_\
#   __/ |           ops scripts
#  |___/
# -----------------------------------------------
#!/bin/bash
# shellcheck disable=SC2124,SC2145,SC2294,SC2086

# The script is used to backup the mariadb database in the openstack namespace
# The script will create a backup directory in the HOME directory with the current timestamp
# The script will dump all the databases except the performance_schema and information_schema
# The script will use the root password from the mariadb secret to connect to the database
# The script will use a node InternalIP + the mariadb-cluster-primary NodePort to connect
# (overseer cannot reach ClusterIP/pod IPs, so NodePort is required from outside the cluster)
# The script will use the --column-statistics=0 option if available in the mysqldump command
# The script will create a separate dump file for each database

set -e
set -o pipefail

BACKUP_DIR="${HOME}/backup/mariadb/$(date +%s)"
MYSQL_PASSWORD="$(kubectl --namespace openstack get secret mariadb -o jsonpath='{.data.root-password}' | base64 -d)"
# Overseer cannot reach ClusterIP/pod IPs. Use a Ready node's InternalIP + the
# service NodePort (resolved at runtime). Pod recreate is fine: NodePort hits
# Service endpoints, not pod IPs, so host/port stay valid across IP churn.
# Print first Ready InternalIP but keep reading stdin so kubectl is not SIGPIPE'd under pipefail.
MYSQL_HOST=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | awk '$1 == "True" && !found { print $2; found=1 } END { exit !found }')
MYSQL_PORT=$(kubectl -n openstack get service mariadb-cluster-primary -o jsonpath='{.spec.ports[0].nodePort}')
if [[ -z "${MYSQL_HOST}" || -z "${MYSQL_PORT}" ]]; then
    echo "Failed to resolve a Ready node InternalIP or mariadb-cluster-primary NodePort" >&2
    exit 1
fi

if mysqldump --help | grep -q column-statistics; then
    MYSQL_DUMP_COLLUMN_STATISTICS="--column-statistics=0"
else
    MYSQL_DUMP_COLLUMN_STATISTICS=""
fi

mkdir -p "${BACKUP_DIR}"

pushd "${BACKUP_DIR}"
    mysql -h ${MYSQL_HOST} \
        -P ${MYSQL_PORT} \
        -u root \
        -p${MYSQL_PASSWORD} \
        -e 'show databases;' \
        --column-names=false \
        --vertical | \
            awk '/[:alnum:]/ && ! /performance_schema/ && ! /information_schema/' | \
                xargs -i mysqldump --host=${MYSQL_HOST} --port=${MYSQL_PORT} ${MYSQL_DUMP_COLLUMN_STATISTICS} \
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
