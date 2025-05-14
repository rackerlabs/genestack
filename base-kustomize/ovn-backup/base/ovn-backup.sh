#!/bin/bash

if [[ "$LOG_LEVEL" == "DEBUG" ]]
then
    set -x
fi

log_level() {
    local LEVEL="$1"
    case "$LEVEL" in
      DEBUG)
        echo 5
        ;;
      INFO)
        echo 4
        ;;
      WARNING)
        echo 3
        ;;
      ERROR)
        echo 2
        ;;
      CRITICAL)
        echo 1
        ;;
      *)
        exit 3
        ;;
    esac
}

log_line() {
    local LEVEL
    LEVEL="$(log_level "$1")"
    if [[ "$LEVEL" -le "$(log_level "$LOG_LEVEL")" ]]
    then
        local line
        line=$(date +"%b %d %H:%M:%S $*")
        echo "$line" | tee -a "$LOG_FILE"
    fi
}

# Stats files init. These mostly get used to send to Prometheus, but you could
# just read them if you want to.

STATS_DIR="${BACKUP_DIR}/stats"

[[ -d "$STATS_DIR" ]] || mkdir "$STATS_DIR"

declare -A metric_types=(
    ["run_count"]="counter"
    ["run_timestamp"]="counter"
    ["save_pairs_to_disk_success_count"]="counter"
    ["save_pairs_to_disk_success_timestamp"]="counter"
    ["save_pairs_to_disk_failure_count"]="counter"
    ["save_pairs_to_disk_failure_timestamp"]="counter"
    ["upload_attempt_count"]="counter"
    ["upload_attempt_timestamp"]="counter"
    ["upload_pairs_success_count"]="counter"
    ["upload_pairs_success_timestamp"]="counter"
    ["upload_pairs_failure_count"]="counter"
    ["upload_pairs_failure_timestamp"]="counter"
    ["disk_files_gauge"]="gauge"
    ["disk_used_percent_gauge"]="gauge"
    ["swift_objects_gauge"]="gauge"
)

# Initialize metrics/stats files with 0 if they don't exist
for metric_filename in "${!metric_types[@]}"
do
    metric_file_fullname="${STATS_DIR}/$metric_filename"
    [[ -e "$metric_file_fullname" ]] || echo "0" > "$metric_file_fullname"
done

# get_metric takes the metric name, reads the metric file, and echos the value
get_metric() {
    local STAT_NAME
    local STAT_FULL_FILENAME
    STAT_NAME="$1"
    STAT_FULL_FILENAME="${STATS_DIR}/$STAT_NAME"
    VALUE="$(cat "$STAT_FULL_FILENAME")"
    echo "$VALUE"
}

# update count $1: stat name, $2 new value
# Used for updating disk file count and Cloud Files object counts.
update_metric() {
    local STAT_NAME
    local VALUE
    STAT_NAME="$1"
    VALUE="$2"
    STAT_FULL_FILENAME="${STATS_DIR}/$STAT_NAME"
    echo "$VALUE" > "$STAT_FULL_FILENAME"
}

# increment increments a stats counter $1 by 1
increment() {
    local VALUE
    local METRIC_NAME
    METRIC_NAME="$1"
    VALUE="$(get_metric "$METRIC_NAME")"
    ((VALUE++))
    update_metric "$METRIC_NAME" "$VALUE"
}

# Save epoch time to metric $1
timestamp_metric() {
    local METRIC_NAME
    METRIC_NAME="$1"
    update_metric "$METRIC_NAME" "$(date +%s)"
}

increment run_count
timestamp_metric run_timestamp

finalize_and_upload_metrics() {
    local FILE_COUNT
    FILE_COUNT=$(find "$BACKUP_DIR" -name \*.backup | wc -l)
    update_metric disk_files_gauge "$FILE_COUNT"
    local DISK_PERCENT_USED
    DISK_PERCENT_USED=$(df "$BACKUP_DIR" | perl -lane 'next unless $. == 2; print int($F[4])')
    update_metric disk_used_percent_gauge "$DISK_PERCENT_USED"
    local OBJECT_COUNT
    if [[ "$SWIFT_TEMPAUTH_UPLOAD" == "true" ]]
    then
        OBJECT_COUNT=$($SWIFT stat "$CONTAINER" | awk '/Objects:/ { print $2 }')
        update_metric swift_objects_gauge "$OBJECT_COUNT"
    fi

    if [[ "$PROMETHEUS_UPLOAD" != "true" ]]
    then
        exit 0
    fi

    for metric in "${!metric_types[@]}"
    do
        echo "# TYPE $metric ${metric_types[$metric]}
$metric{label=\"ovn-backup\"} $(get_metric "$metric")" | \
        curl -sS \
          "$PROMETHEUS_PUSHGATEWAY_URL/metrics/job/$PROMETHEUS_JOB_NAME" \
          --data-binary @-
    done

    # Put metrics in the log if running at DEBUG level.
    perl -ne 'print "$ARGV $_"' /backup/stats/* | cut -d / -f 4 | \
    while read -r read_metric
    do
        log_line DEBUG "run end metric $read_metric"
    done
}
trap finalize_and_upload_metrics EXIT INT TERM HUP

# Delete old backup files on volume.
cd "$BACKUP_DIR" || exit 2
[[ -e "$BACKUP_DIR/last_upload" ]] || touch "$BACKUP_DIR/last_upload" || exit 3
find "$BACKUP_DIR" -ctime +"$RETENTION_DAYS" -delete;

# Make a backup in YYYY/MM/DD directory in $BACKUP_DIR
YMD="$(date +"%Y/%m/%d")"
# kubectl-ko creates backups in $PWD, so we cd first.
mkdir -p "$YMD" && cd "$YMD" || exit 2

# This treats the saved failed and success count as a single metric for both
# backups; if either one fails, we increment the failure count, otherwise,
# the success count.
FAILED=false
if ! /kube-ovn/kubectl-ko nb backup
then
    log_line ERROR "nb backup failed"
    FAILED=true
fi
if ! /kube-ovn/kubectl-ko sb backup
then
    log_line ERROR "sb backup failed"
    FAILED=true
fi
if [[ "$FAILED" == "true" ]]
then
    increment save_pairs_to_disk_failure_count
    timestamp_metric save_pairs_to_disk_failure_timestamp
else
    increment save_pairs_to_disk_success_count
    timestamp_metric save_pairs_to_disk_success_timestamp
fi

# compressing the OVN backups, if created successfully, before uploading to swift container
find . -name "*.backup" | \
while read -r file
do
    if gzip "$file"
    then
      log_line INFO "$file compressed successfully to ${file}.gz"
    else
      log_line ERROR "Error compressing file"
    fi
done

if [[ "$SWIFT_TEMPAUTH_UPLOAD" != "true" ]]
then
    exit 0
fi

# Everything from here forward deals with uploading to a Swift with tempauth.

cd "$BACKUP_DIR" || exit 2

increment upload_attempt_count
timestamp_metric upload_attempt_timestamp

# Make a working "swift" command
SWIFT="kubectl -n openstack exec -i openstack-admin-client --
env -i ST_AUTH=$ST_AUTH ST_USER=$ST_USER ST_KEY=$ST_KEY
/var/lib/openstack/bin/swift"

# Create the container if it doesn't exist
if ! $SWIFT stat "$CONTAINER" > /dev/null
then
  $SWIFT post "$CONTAINER"
fi

# upload_file uploads $1 to the container
upload_file() {
    FILE="$1"
    # Using OBJECT_NAME instead of FILE every time doesn't change the behavior,
    # but stops shellcheck from identifying this as trying to read and write
    # the same file.
    OBJECT_NAME="$FILE"
    # Delete swift uploaded object after calculated seconds for RETENTION_DAYS, ie. 30 days from now.
    SECONDS=$(date -d "+$RETENTION_DAYS days" +%s)
    if $SWIFT upload "$CONTAINER" --object-name "$OBJECT_NAME" -H "X-Delete-After:$SECONDS" - < "$FILE"
    then
      log_line INFO "SUCCESSFUL UPLOAD $FILE as object $OBJECT_NAME to container $CONTAINER"
    else
      log_line ERROR "FAILURE API swift exited $? uploading $FILE as $OBJECT_NAME to container $CONTAINER"
      FAILED_UPLOAD=true
    fi
}

# find created backups and upload them
cd "$BACKUP_DIR" || exit 2

FAILED_UPLOAD=false
find "$YMD" -type f -newer "$BACKUP_DIR/last_upload" | \
while read -r file
do
    upload_file "$file"
done

if [[ "$FAILED_UPLOAD" == "true" ]]
then
    increment upload_pairs_failure_count
    timestamp_metric upload_pairs_failure_timestamp
else
    increment upload_pairs_success_count
    timestamp_metric upload_pairs_success_timestamp
fi

touch "$BACKUP_DIR/last_upload"
