#!/bin/bash
# Genestack Test Orchestrator
# Runs test suites based on specified test level

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default test level
TEST_LEVEL="${1:-standard}"

# Test results directory
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-/tmp/test-results}"
AGGREGATE_RESULTS="${TEST_RESULTS_DIR}/aggregate-results.txt"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage information
usage() {
    cat << EOF
Usage: $0 [TEST_LEVEL]

Run Genestack test suites at the specified level.

TEST_LEVEL options:
  quick      - Run only Kubernetes health tests (fastest, ~30 seconds)
  standard   - Run K8s, infrastructure, and service tests (default, ~2 minutes)
  full       - Run all tests including smoke tests (~5-10 minutes)

Environment variables:
  TEST_RESULTS_DIR - Directory to store test results (default: /tmp/test-results)

Examples:
  $0 quick          # Quick validation
  $0 standard       # Standard test suite
  $0 full           # Complete validation

EOF
    exit 1
}

# Print banner
print_banner() {
    echo ""
    echo "=========================================="
    echo "  Genestack Testing Framework"
    echo "=========================================="
    echo "Test Level: ${TEST_LEVEL}"
    echo "Results Dir: ${TEST_RESULTS_DIR}"
    echo "=========================================="
    echo ""
}

# Run a test script
run_test_script() {
    local script_name="$1"
    local script_path="${SCRIPT_DIR}/${script_name}"
    local test_name=$(basename "${script_name}" .sh)

    if [ ! -f "${script_path}" ]; then
        echo -e "${RED}ERROR: Test script not found: ${script_path}${NC}"
        return 1
    fi

    echo ""
    echo -e "${BLUE}=========================================="
    echo -e "Running: ${test_name}"
    echo -e "==========================================${NC}"
    echo ""

    # Run the test script
    if bash "${script_path}"; then
        echo -e "${GREEN}✓ ${test_name} PASSED${NC}"
        echo "${test_name}: PASSED" >> "${AGGREGATE_RESULTS}"
        return 0
    else
        echo -e "${RED}✗ ${test_name} FAILED${NC}"
        echo "${test_name}: FAILED" >> "${AGGREGATE_RESULTS}"
        return 1
    fi
}

# Aggregate and display results
aggregate_results() {
    local total_suites=0
    local passed_suites=0
    local failed_suites=0

    echo ""
    echo "=========================================="
    echo "Test Suite Results Summary"
    echo "=========================================="
    echo ""

    if [ -f "${AGGREGATE_RESULTS}" ]; then
        while IFS=: read -r suite status; do
            ((total_suites++))
            if [ "${status}" = " PASSED" ]; then
                ((passed_suites++))
                echo -e "${GREEN}✓${NC} ${suite}: PASSED"
            else
                ((failed_suites++))
                echo -e "${RED}✗${NC} ${suite}: FAILED"
            fi
        done < "${AGGREGATE_RESULTS}"
    fi

    echo ""
    echo "=========================================="
    echo "Total Test Suites: ${total_suites}"
    echo -e "Passed: ${GREEN}${passed_suites}${NC}"
    echo -e "Failed: ${RED}${failed_suites}${NC}"
    echo "=========================================="
    echo ""

    # Combine all XML results into a single file
    if ls "${TEST_RESULTS_DIR}"/results.xml* >/dev/null 2>&1; then
        echo "Individual test results available in: ${TEST_RESULTS_DIR}"
    fi

    return ${failed_suites}
}

# Main execution
main() {
    # Check arguments
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
    fi

    # Validate test level
    case "${TEST_LEVEL}" in
        quick|standard|full)
            ;;
        *)
            echo -e "${RED}ERROR: Invalid test level: ${TEST_LEVEL}${NC}"
            echo ""
            usage
            ;;
    esac

    # Create results directory
    mkdir -p "${TEST_RESULTS_DIR}"
    rm -f "${AGGREGATE_RESULTS}"

    print_banner

    local overall_result=0

    # Quick level: Kubernetes health tests only
    if [ "${TEST_LEVEL}" = "quick" ] || [ "${TEST_LEVEL}" = "standard" ] || [ "${TEST_LEVEL}" = "full" ]; then
        run_test_script "test-k8s-health.sh" || overall_result=1
    fi

    # Standard level: Add infrastructure and service tests
    if [ "${TEST_LEVEL}" = "standard" ] || [ "${TEST_LEVEL}" = "full" ]; then
        run_test_script "test-openstack-infra.sh" || overall_result=1
        run_test_script "test-openstack-services.sh" || overall_result=1
    fi

    # Full level: Add smoke tests
    if [ "${TEST_LEVEL}" = "full" ]; then
        run_test_script "test-openstack-smoke.sh" || overall_result=1
    fi

    # Display aggregate results
    echo ""
    aggregate_results
    local aggregate_result=$?

    # Final status
    echo ""
    if [ ${aggregate_result} -eq 0 ]; then
        echo -e "${GREEN}=========================================="
        echo -e "  ALL TESTS PASSED ✓"
        echo -e "==========================================${NC}"
        exit 0
    else
        echo -e "${RED}=========================================="
        echo -e "  SOME TESTS FAILED ✗"
        echo -e "==========================================${NC}"
        exit 1
    fi
}

# Trap errors
trap 'echo -e "${RED}An error occurred. Test execution failed.${NC}"; exit 1' ERR

# Run main
main "$@"
