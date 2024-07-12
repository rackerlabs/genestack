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
export -f log_level

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
export -f log_line # exported for upload_file

# Delete old backup files on volume.
cd "$BACKUP_DIR" || exit 2
[[ -e "$BACKUP_DIR/last_upload" ]] || touch "$BACKUP_DIR/last_upload" || exit 3
find "$BACKUP_DIR" -ctime +"$RETENTION_DAYS" -delete;

# Make a backup in YYYY/MM/DD directory in $BACKUP_DIR
YMD="$(date +"%Y/%m/%d")"
# kubectl-ko creates backups in $PWD, so we cd first.
mkdir -p "$YMD" && cd "$YMD" || exit 2
/kube-ovn/kubectl-ko nb backup || log_line ERROR "nb backup failed"
/kube-ovn/kubectl-ko sb backup || log_line ERROR "sb backup failed"

if [[ "$SWIFT_TEMPAUTH_UPLOAD" != "true" ]]
then
    exit 0
fi

# Everything from here forward deals with uploading to a Swift with tempauth.

cd "$BACKUP_DIR" || exit 2

# Make a working "swift" command
SWIFT="kubectl -n openstack exec -i openstack-admin-client --
env -i ST_AUTH=$ST_AUTH ST_USER=$ST_USER ST_KEY=$ST_KEY
/var/lib/openstack/bin/swift"
export SWIFT

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
    if $SWIFT upload "$CONTAINER" --object-name "$OBJECT_NAME" - < "$FILE"
    then
      log_line INFO "SUCCESSFUL UPLOAD $FILE as object $OBJECT_NAME"
    else
      log_line ERROR "FAILURE API swift exited $? uploading $FILE as $OBJECT_NAME"
    fi
}
export -f upload_file

# find created backups and upload them
cd "$BACKUP_DIR" || exit 2
# unusual find syntax to use an exported function from the shell
find "$YMD" -type f -newer "$BACKUP_DIR/last_upload" \
-exec bash -c 'upload_file "$0"' {} \;
touch "$BACKUP_DIR/last_upload"
