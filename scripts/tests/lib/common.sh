#!/bin/bash
# Common test utilities for Genestack testing framework
# Provides JUnit XML output generation for GitHub Actions integration

set -eo pipefail

# Configuration
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-/tmp/test-results}"
TEST_SUITE_NAME="${TEST_SUITE_NAME:-genestack-tests}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TOTAL_TESTS=0

# JUnit XML storage
JUNIT_XML=""

# Initialize test framework
# Creates results directory and starts JUnit XML output
init_tests() {
    local suite_name="${1:-${TEST_SUITE_NAME}}"

    mkdir -p "${TEST_RESULTS_DIR}"

    # Initialize JUnit XML structure
    JUNIT_XML="<?xml version='1.0' encoding='UTF-8'?>\n"
    JUNIT_XML+="<testsuite name='${suite_name}' timestamp='${TIMESTAMP}'>\n"

    echo "=========================================="
    echo "Starting test suite: ${suite_name}"
    echo "Results will be saved to: ${TEST_RESULTS_DIR}"
    echo "=========================================="
}

# Run a single test
# Arguments:
#   $1 - Test name (displayed in output and JUnit)
#   $2 - Test function to execute
run_test() {
    local test_name="$1"
    local test_func="$2"
    local start_time=$(date +%s.%N)
    local output=""
    local exit_code=0

    ((TOTAL_TESTS++))

    echo -n "Running test: ${test_name}... "

    # Execute test and capture output
    if output=$($test_func 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    # Record result
    if [ ${exit_code} -eq 0 ]; then
        echo "PASSED"
        ((TESTS_PASSED++))
        record_test_result "${test_name}" "passed" "" "${output}" "${duration}"
    else
        echo "FAILED"
        ((TESTS_FAILED++))
        record_test_result "${test_name}" "failed" "${output}" "" "${duration}"
    fi
}

# Skip a test with a reason
# Arguments:
#   $1 - Test name
#   $2 - Skip reason
skip_test() {
    local test_name="$1"
    local skip_reason="$2"

    ((TOTAL_TESTS++))
    ((TESTS_SKIPPED++))

    echo "Skipping test: ${test_name} - ${skip_reason}"
    record_test_result "${test_name}" "skipped" "${skip_reason}" "" "0"
}

# Record test result in JUnit XML format
# Arguments:
#   $1 - Test name
#   $2 - Status (passed/failed/skipped)
#   $3 - Failure/skip message
#   $4 - Output (for passed tests)
#   $5 - Duration in seconds
record_test_result() {
    local name="$1"
    local status="$2"
    local failure_msg="$3"
    local output="$4"
    local duration="${5:-0}"

    # Escape XML special characters
    name=$(echo "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
    failure_msg=$(echo "$failure_msg" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    output=$(echo "$output" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    JUNIT_XML+="  <testcase name='${name}' classname='${TEST_SUITE_NAME}' time='${duration}'>\n"

    if [ "${status}" = "failed" ]; then
        JUNIT_XML+="    <failure message='Test failed'><![CDATA[\n${failure_msg}\n]]></failure>\n"
    elif [ "${status}" = "skipped" ]; then
        JUNIT_XML+="    <skipped message='${failure_msg}'/>\n"
    fi

    JUNIT_XML+="  </testcase>\n"
}

# Finalize tests and write results
# Exits with non-zero code if any tests failed
finalize_tests() {
    # Close JUnit XML
    JUNIT_XML+="</testsuite>\n"

    # Write results file
    local results_file="${TEST_RESULTS_DIR}/results.xml"
    echo -e "${JUNIT_XML}" > "${results_file}"

    # Print summary
    echo "=========================================="
    echo "Test Suite Completed: ${TEST_SUITE_NAME}"
    echo "=========================================="
    echo "Total Tests:   ${TOTAL_TESTS}"
    echo "Passed:        ${TESTS_PASSED}"
    echo "Failed:        ${TESTS_FAILED}"
    echo "Skipped:       ${TESTS_SKIPPED}"
    echo "=========================================="
    echo "Results saved to: ${results_file}"
    echo "=========================================="

    # Exit with appropriate code
    if [ ${TESTS_FAILED} -gt 0 ]; then
        echo "FAILURE: Some tests failed"
        return 1
    else
        echo "SUCCESS: All tests passed"
        return 0
    fi
}

# Helper: Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper: Wait for condition with timeout
# Arguments:
#   $1 - Timeout in seconds
#   $2 - Check command (should return 0 on success)
#   $3 - Description
wait_for_condition() {
    local timeout="$1"
    local check_cmd="$2"
    local description="${3:-condition}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if eval "$check_cmd" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
        ((elapsed+=2))
    done

    echo "Timeout waiting for ${description}"
    return 1
}

# Helper: Retry command with exponential backoff
# Arguments:
#   $1 - Max attempts
#   $2 - Command to execute
retry_command() {
    local max_attempts="$1"
    shift
    local cmd="$@"
    local attempt=1
    local delay=2

    while [ $attempt -le $max_attempts ]; do
        if eval "$cmd"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Attempt $attempt failed, retrying in ${delay}s..."
            sleep $delay
            delay=$((delay * 2))
        fi

        ((attempt++))
    done

    return 1
}
