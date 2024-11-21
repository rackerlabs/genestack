#!/bin/bash

CHART="$1"
shift # preserve "$@" for --post-renderer-args

GENESTACK_DIR="${GENESTACK_DIR:-/opt/genestack}"
CHART_META_FILE=\
"${CHART_META_FILE:-$GENESTACK_DIR/bin/chart-install-meta.yaml}"
GENESTACK_CONFIG_DIR="${GENESTACK_CONFIG_DIR:-/etc/genestack}"
GENESTACK_CHART_DIR=\
"${GENESTACK_CHART_DIR:-$GENESTACK_DIR/base-helm-configs/$CHART}"
GENESTACK_CHART_CONFIG_DIR=\
"${GENESTACK_CHART_CONFIG_DIR:-$GENESTACK_CONFIG_DIR/helm-configs/$CHART}"
# This Python needs PyYAML, which the normal Genestack venv will have.
YAML_PARSER_PYTHON="${YAML_PARSER_PYTHON:-$(which python)}"
YAML_PARSER_PY="${YAML_PARSER_PY:-$GENESTACK_DIR/bin/yamlparse.py}"
YAML_PARSER_CMD="${YAML_PARSER_CMD:-$YAML_PARSER_PYTHON $YAML_PARSER_PY}"

IFS= readarray -t chart_values < <($YAML_PARSER_CMD "$CHART_META_FILE" "$CHART")

values_length=${#chart_values[@]}

# This for loop takes values from the YAML file `namespace: prometheus` and
# sets variables like NAMESPACE=prometheus for use by the script.
for (( i=0; i<values_length; i+=2 ))
do
    var_name="$(echo "${chart_values[i]}" | tr '[:lower:]' '[:upper:]')"
    declare "$var_name=${chart_values[i+1]}"
done

required_vars=("NAMESPACE" "NAME" "REPONAME" "RELEASENAME" "REPO")
for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        echo "ERROR: Required variable $var is missing in the YAML file."
        exit 1
    fi
done

# Though it probably wouldn't make any difference for all of the
# $GENESTACK_CONFIG_DIR files to come last, this takes care to fully preserve
# the order
echo "Including overrides in order:"
if [[ "$VALUESFILES" == "" ]]
then
    echo "WARNING: no values files specified. Check valuesFiles in the YAML file for $CHART"
fi
values_args=()
set -o noglob # Prevent glob expansions in $VALUESFILES
for BASE_FILENAME in $VALUESFILES
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

# Run script as ECHO_TEST=true install-chart.sh to see the commands that would
# run formatted as a Python list to clearly distinguish whitespace from separate
# arguments
run_or_test_print () {
    if [[ "$ECHO_TEST" == "true" ]]
    then
        $YAML_PARSER_PYTHON -c 'import sys; print(sys.argv[1:])' "$@"
    else
        "$@"
    fi
}

run_or_test_print helm repo add "$REPONAME" "$REPO"
run_or_test_print helm repo update
run_or_test_print helm upgrade --install "$RELEASENAME" "$REPONAME/$NAME" \
    --create-namespace --namespace="$NAMESPACE" \
    --timeout 10m \
    "${values_args[@]}" \
    --post-renderer "$GENESTACK_CONFIG_DIR/kustomize/kustomize.sh" \
    --post-renderer-args "$CHART/overlay" "$@"
