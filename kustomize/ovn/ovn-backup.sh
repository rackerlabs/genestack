#!/bin/bash

if [[ "$LOG_LEVEL" == "DEBUG" ]]
then
    set -x
fi

SWIFT_CONTAINER_BASE_URL="$SWIFT_BASE_URL/swift/v1"
export SWIFT_CONTAINER_BASE_URL

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
    if [[ "$LEVEL" -ge "$LOG_LEVEL" ]]
    then
        local line
        line=$(date +"%b %d %H:%M:%S $*")
        echo "$line" | tee -a "$LOG_FILE"
    fi
}
export -f log_line # exported for upload_file

# Delete old backup files on volume.
cd "$BACKUP_DIR" || exit 2
find "$BACKUP_DIR" -ctime +"$RETENTION_DAYS" -delete;

# Make a backup in YYYY/MM/DD directory in $BACKUP_DIR
YMD="$(date +"%Y/%m/%d")"
mkdir -p "$YMD" && cd "$YMD" || exit 2 # kubectl-ko creates backups in $PWD, so we cd first.
/kube-ovn/kubectl-ko nb backup || log_line ERROR "nb backup failed"
/kube-ovn/kubectl-ko sb backup || log_line ERROR "sb backup failed"

if [[ "$SWIFT_UPLOAD" != "true" ]]
then
    exit 0
fi

# Everything from here forward deals with uploading to Rackspace OSPCv1 Cloud
# Files.

cd "$BACKUP_DIR" || exit 2
CURL="$(which curl)"
export CONTAINER CURL # these need to reach the subshell below used with `find`
HEADER_TEMP_FILE=$(mktemp /tmp/headers.XXXXXXXX)
$CURL -sS -D "$HEADER_TEMP_FILE" -H "X-Auth-User: $USERNAME" -H "X-Auth-Key: $SECRET_KEY" "$SWIFT_BASE_URL/auth/v1.1"
sed -i -e 's/\r//g' "$HEADER_TEMP_FILE" # strip carriage returns
token=$(awk '/X-Auth-Token/ { print $2 }' "$HEADER_TEMP_FILE")
rm "$HEADER_TEMP_FILE"
export token

# wrap curl with some things we will always use
curl_wrap() {
    $CURL -sS -H "X-Auth-Token: $token" "$@"
}
export -f curl_wrap

# Create the container if it doesn't exist
# TODO fixme
check_container=$(curl_wrap -o /dev/null -w "%{http_code}" "$SWIFT_CONTAINER_BASE_URL/$CONTAINER")
if ! [[ "$check_container" =~ 20[0-9] ]]
then
  curl_wrap -X PUT "$SWIFT_CONTAINER_BASE_URL/$CONTAINER"
fi

# upload_file uploads $1 to the CF container
upload_file() {
    FILE="$1"
    local curl_return
    curl_return=$(curl_wrap -w "%{http_code}" \
      -X PUT "${SWIFT_CONTAINER_BASE_URL}/${CONTAINER}/$FILE" -T "$FILE")
    if [[ "$curl_return" == "201" ]]
    then
      log_line INFO "SUCCESSFUL UPLOAD $FILE"
    else
      log_line ERROR "FAILURE API returned $curl_return uploading $FILE (expected 201)"
    fi
}
export -f upload_file

# find created backups and upload them
cd "$BACKUP_DIR" || exit 2
# unusual find syntax to use an exported function from the shell
find "$YMD" -type f -exec bash -c 'upload_file "$0"' {} \;
