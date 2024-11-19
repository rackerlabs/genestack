#!/bin/bash

# Using a first arg of '-t' will just echo commands
if [[ "$1" == "-t" ]]
then
    ECHOTEST="echo "
    shift
fi
CHART="$1"
shift # preserve "$@" for --post-renderer-args
GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
CHART_META_FILE=\
"${CHART_META_FILE:-$GENESTACK_DIR/bin/chart-install-meta.yaml}"

if ! GOJQ="$(command -v gojq)"
then
    echo "Please install gojq for reading $CHART_META_FILE"
    exit 1
fi

get_chart_info() {
    local LIST=""
    if [[ "$1" == "-l" ]]
    then
        local LIST=" | .[]"
        shift
    fi
    local CHART="$1"
    local PARAM="$2"
    local result
    result="$($GOJQ -r --yaml-input ".$CHART.$PARAM$LIST" "$CHART_META_FILE")"
    if [[ "$result" == "null" ]]
    then
        echo "missing \"$CHART\" parameter \"$PARAM\"" > /dev/fd/2
        exit 1
    else
        echo "$result"
    fi
}

for var in repo helm_release_name chart_name url namespace
do
    var_name="$(echo "$var" | tr '[:lower:]' '[:upper:]')"
    declare "$var_name=$(get_chart_info "$CHART" "$var")"
done

GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"

GENESTACK_CHART_DIR=\
"${GENESTACK_CHART_DIR:-$GENESTACK_DIR/base-helm-configs/$CHART}"
GENESTACK_CHART_CONFIG_DIR=\
"${GENESTACK_CHART_CONFIG_DIR:-$GENESTACK_CONFIG_DIR/helm-configs/$CHART}"

# Though it probably wouldn't make any difference for all of the
# $GENESTACK_CONFIG_DIR files to come last, this takes care to fully preserve
# the order
echo "Including overrides in order:"
values_args=()
for BASE_FILENAME in $(get_chart_info -l "$CHART" values_files)
do
    for DIR in "$GENESTACK_CHART_DIR" "$GENESTACK_CHART_CONFIG_DIR"
    do
        ABSOLUTE_PATH="$DIR/$BASE_FILENAME"
        if [[ -e "$ABSOLUTE_PATH" ]]
        then
            echo "    $ABSOLUTE_PATH"
            values_args+=("--values" "$ABSOLUTE_PATH")
        fi
    done
done
echo

$ECHOTEST helm repo add "$REPO" "$URL"
$ECHOTEST helm repo update
$ECHOTEST helm upgrade --install "$HELM_RELEASE_NAME" "$REPO/$CHART_NAME" \
    --create-namespace --namespace="$NAMESPACE" \
    --timeout 10m \
    "${values_args[@]}" \
    --post-renderer "$GENESTACK_DIR/base-kustomize/kustomize.sh" \
    --post-renderer-args "$CHART/base" "$@"
