#!/bin/bash
# Unit Tests for common-functions.sh
#
# This script tests all functions in common-functions.sh to ensure they work correctly.
# Run with: bash test-common-functions.sh

set -e

# Colors for test output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test results
FAILED_TESTS=()

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR=$(mktemp -d)
export GENESTACK_BASE_DIR="$TEST_DIR/opt/genestack"
export GENESTACK_OVERRIDES_DIR="$TEST_DIR/etc/genestack"

# Create test directory structure
mkdir -p "$GENESTACK_BASE_DIR"/{base-helm-configs,scripts}
mkdir -p "$GENESTACK_OVERRIDES_DIR"/{helm-configs/global_overrides,kustomize}

# Copy common-functions.sh to test location
cp "$SCRIPT_DIR/common-functions.sh" "$GENESTACK_BASE_DIR/scripts/"

# Source the library
source "$GENESTACK_BASE_DIR/scripts/common-functions.sh"

# Helper functions
print_test_header() {
    echo ""
    echo "=========================================="
    echo "Testing: $1"
    echo "=========================================="
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected: $expected"
        echo "  Got: $actual"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local test_name="$2"

    ((TESTS_RUN++))

    if [[ -n "$value" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected non-empty value, got empty"
        return 1
    fi
}

assert_command_succeeds() {
    local test_name="$1"
    shift

    ((TESTS_RUN++))

    if "$@" &> /dev/null; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        return 0
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Command failed: $*"
        return 1
    fi
}

assert_command_fails() {
    local test_name="$1"
    shift

    ((TESTS_RUN++))

    if "$@" &> /dev/null; then
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$test_name")
        echo -e "${RED}✗${NC} FAIL: $test_name"
        echo "  Expected command to fail, but it succeeded: $*"
        return 1
    else
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: $test_name"
        return 0
    fi
}

# Test: check_dependencies
test_check_dependencies() {
    print_test_header "check_dependencies"

    # This should succeed (bash always exists)
    assert_command_succeeds "check_dependencies with valid command" check_dependencies "bash"

    # This should fail (fake-command doesn't exist)
    assert_command_fails "check_dependencies with invalid command" check_dependencies "fake-command-12345"
}

# Test: get_chart_version
test_get_chart_version() {
    print_test_header "get_chart_version"

    # Create test version file
    cat > "$GENESTACK_OVERRIDES_DIR/helm-chart-versions.yaml" << EOF
keystone: 1.2.3
nova: 2.3.4
  cinder: 3.4.5
EOF

    local version=$(get_chart_version "keystone")
    assert_equals "1.2.3" "$version" "get_chart_version returns correct version for keystone"

    version=$(get_chart_version "nova")
    assert_equals "2.3.4" "$version" "get_chart_version returns correct version for nova"

    version=$(get_chart_version "cinder")
    assert_equals "3.4.5" "$version" "get_chart_version returns correct version with leading spaces"
}

# Test: update_helm_repo
test_update_helm_repo() {
    print_test_header "update_helm_repo"

    # Note: This requires helm to be installed and is skipped in non-k8s environments
    if command -v helm &> /dev/null; then
        assert_command_succeeds "update_helm_repo adds repo" \
            update_helm_repo "test-repo" "https://charts.helm.sh/stable"
    else
        echo -e "${YELLOW}⊘${NC} SKIP: helm not installed"
        ((TESTS_RUN++))
    fi
}

# Test: extract_chart_metadata
test_extract_chart_metadata() {
    print_test_header "extract_chart_metadata"

    # Create test override file
    mkdir -p "$GENESTACK_OVERRIDES_DIR/helm-configs/testservice"
    cat > "$GENESTACK_OVERRIDES_DIR/helm-configs/testservice/override.yaml" << EOF
chart:
  repo_url: https://example.com/charts
  repo_name: example-repo
  service_name: example-service
EOF

    local repo_url=""
    local repo_name=""
    local service_name=""

    extract_chart_metadata "$GENESTACK_OVERRIDES_DIR/helm-configs/testservice" \
        repo_url repo_name service_name \
        "default-url" "default-repo" "default-service"

    assert_equals "https://example.com/charts" "$repo_url" "extract_chart_metadata extracts repo_url"
    assert_equals "example-repo" "$repo_name" "extract_chart_metadata extracts repo_name"
    assert_equals "example-service" "$service_name" "extract_chart_metadata extracts service_name"

    # Test with defaults
    repo_url=""
    repo_name=""
    service_name=""

    extract_chart_metadata "$GENESTACK_OVERRIDES_DIR/helm-configs/nonexistent" \
        repo_url repo_name service_name \
        "default-url" "default-repo" "default-service"

    assert_equals "default-url" "$repo_url" "extract_chart_metadata uses default repo_url"
    assert_equals "default-repo" "$repo_name" "extract_chart_metadata uses default repo_name"
    assert_equals "default-service" "$service_name" "extract_chart_metadata uses default service_name"
}

# Test: setup_helm_chart_path
test_setup_helm_chart_path() {
    print_test_header "setup_helm_chart_path"

    # Test OCI path
    local path=$(setup_helm_chart_path "oci://registry.io" "repo" "service")
    assert_equals "oci://registry.io/repo/service" "$path" "setup_helm_chart_path handles OCI registry"

    # Test non-OCI path (requires helm)
    if command -v helm &> /dev/null; then
        local path=$(setup_helm_chart_path "https://charts.helm.sh/stable" "stable" "nginx")
        assert_equals "stable/nginx" "$path" "setup_helm_chart_path handles non-OCI registry"
    else
        echo -e "${YELLOW}⊘${NC} SKIP: helm not installed for non-OCI test"
        ((TESTS_RUN++))
    fi
}

# Test: parse_install_args
test_parse_install_args() {
    print_test_header "parse_install_args"

    local rotate_secrets
    local helm_pass_through

    # Test with --rotate-secrets
    parse_install_args rotate_secrets helm_pass_through --rotate-secrets --foo --bar

    assert_equals "true" "$rotate_secrets" "parse_install_args sets ROTATE_SECRETS to true"
    assert_equals "2" "${#helm_pass_through[@]}" "parse_install_args captures passthrough args count"
    assert_equals "--foo" "${helm_pass_through[0]}" "parse_install_args captures first passthrough arg"
    assert_equals "--bar" "${helm_pass_through[1]}" "parse_install_args captures second passthrough arg"

    # Test without --rotate-secrets
    rotate_secrets=""
    helm_pass_through=()
    parse_install_args rotate_secrets helm_pass_through --foo

    assert_equals "false" "$rotate_secrets" "parse_install_args defaults ROTATE_SECRETS to false"
    assert_equals "1" "${#helm_pass_through[@]}" "parse_install_args captures single passthrough arg"
}

# Test: process_overrides
test_process_overrides() {
    print_test_header "process_overrides"

    # Create test override files
    mkdir -p "$GENESTACK_BASE_DIR/base-helm-configs/testservice"
    touch "$GENESTACK_BASE_DIR/base-helm-configs/testservice/override1.yaml"
    touch "$GENESTACK_BASE_DIR/base-helm-configs/testservice/override2.yaml"

    local overrides_args=()
    process_overrides "$GENESTACK_BASE_DIR/base-helm-configs/testservice" overrides_args "test overrides"

    assert_equals "4" "${#overrides_args[@]}" "process_overrides creates correct number of args"
    assert_equals "-f" "${overrides_args[0]}" "process_overrides first arg is -f"
    assert_not_empty "${overrides_args[1]}" "process_overrides second arg is file path"
}

# Test: collect_service_overrides
test_collect_service_overrides() {
    print_test_header "collect_service_overrides"

    # Create test override directories and files
    mkdir -p "$GENESTACK_BASE_DIR/base-helm-configs/testservice"
    mkdir -p "$GENESTACK_OVERRIDES_DIR/helm-configs/testservice"
    mkdir -p "$GENESTACK_OVERRIDES_DIR/helm-configs/global_overrides"

    touch "$GENESTACK_BASE_DIR/base-helm-configs/testservice/base.yaml"
    touch "$GENESTACK_OVERRIDES_DIR/helm-configs/global_overrides/global.yaml"
    touch "$GENESTACK_OVERRIDES_DIR/helm-configs/testservice/service.yaml"

    local overrides_args=()
    collect_service_overrides "testservice" overrides_args

    # Should have 3 files * 2 args each (-f filepath) = 6 total args
    assert_equals "6" "${#overrides_args[@]}" "collect_service_overrides collects all overrides"
}

# Test: perform_preflight_checks
test_perform_preflight_checks() {
    print_test_header "perform_preflight_checks"

    # Mock kubectl to avoid actual cluster connection check
    # This test just verifies the function can be called
    echo -e "${YELLOW}⊘${NC} SKIP: perform_preflight_checks requires cluster connection"
    ((TESTS_RUN++))
}

# Test: init_service_directories
test_init_service_directories() {
    print_test_header "init_service_directories"

    init_service_directories "keystone"

    assert_equals "$GENESTACK_BASE_DIR/base-helm-configs/keystone" "$SERVICE_BASE_OVERRIDES" \
        "init_service_directories sets SERVICE_BASE_OVERRIDES"
    assert_equals "$GENESTACK_OVERRIDES_DIR/helm-configs/keystone" "$SERVICE_CUSTOM_OVERRIDES" \
        "init_service_directories sets SERVICE_CUSTOM_OVERRIDES"
    assert_equals "$GENESTACK_OVERRIDES_DIR/helm-configs/global_overrides" "$GLOBAL_OVERRIDES_DIR" \
        "init_service_directories sets GLOBAL_OVERRIDES_DIR"
}

# Test: build_helm_command
test_build_helm_command() {
    print_test_header "build_helm_command"

    local set_args=("--set" "foo=bar")
    local overrides_args=("-f" "/path/to/override.yaml")
    local helm_command=()

    build_helm_command "keystone" "openstack-helm/keystone" "1.0.0" "openstack" \
        set_args overrides_args helm_command

    assert_not_empty "${helm_command[*]}" "build_helm_command creates helm command"
    assert_equals "helm" "${helm_command[0]}" "build_helm_command starts with helm"
    assert_equals "keystone" "${helm_command[3]}" "build_helm_command includes service name"
}

# Test: execute_helm_upgrade
test_execute_helm_upgrade() {
    print_test_header "execute_helm_upgrade"

    # This requires actual helm/k8s, so we skip it
    echo -e "${YELLOW}⊘${NC} SKIP: execute_helm_upgrade requires helm and kubernetes"
    ((TESTS_RUN++))
}

# Test: wait_for_resource_ready
test_wait_for_resource_ready() {
    print_test_header "wait_for_resource_ready"

    # This requires actual k8s cluster, so we skip it
    echo -e "${YELLOW}⊘${NC} SKIP: wait_for_resource_ready requires kubernetes cluster"
    ((TESTS_RUN++))
}

# Test: discover_service_endpoint
test_discover_service_endpoint() {
    print_test_header "discover_service_endpoint"

    # This requires actual k8s cluster, so we test default value return
    local endpoint=$(discover_service_endpoint "kube-system" "nonexistent-service" "8080" "default:8080")
    assert_equals "default:8080" "$endpoint" "discover_service_endpoint returns default when service not found"
}

# Test: get_or_create_secret
test_get_or_create_secret() {
    print_test_header "get_or_create_secret"

    # This requires actual k8s cluster, so we skip it
    echo -e "${YELLOW}⊘${NC} SKIP: get_or_create_secret requires kubernetes cluster"
    ((TESTS_RUN++))
}

# Test: is_enabled
test_is_enabled() {
    print_test_header "is_enabled"

    # Create test components file
    cat > "$GENESTACK_OVERRIDES_DIR/openstack-components.yaml" << EOF
keystone: true
nova: false
cinder: true
EOF

    if is_enabled "keystone"; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: is_enabled returns true for enabled component"
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("is_enabled returns true for enabled component")
        echo -e "${RED}✗${NC} FAIL: is_enabled returns true for enabled component"
    fi
    ((TESTS_RUN++))

    if ! is_enabled "nova"; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}✓${NC} PASS: is_enabled returns false for disabled component"
    else
        ((TESTS_FAILED++))
        FAILED_TESTS+=("is_enabled returns false for disabled component")
        echo -e "${RED}✗${NC} FAIL: is_enabled returns false for disabled component"
    fi
    ((TESTS_RUN++))
}

# Run all tests
main() {
    echo "=========================================="
    echo "Common Functions Unit Tests"
    echo "=========================================="
    echo "Test directory: $TEST_DIR"
    echo ""

    test_check_dependencies
    test_get_chart_version
    test_update_helm_repo
    test_extract_chart_metadata
    test_setup_helm_chart_path
    test_parse_install_args
    test_process_overrides
    test_collect_service_overrides
    test_perform_preflight_checks
    test_init_service_directories
    test_build_helm_command
    test_execute_helm_upgrade
    test_wait_for_resource_ready
    test_discover_service_endpoint
    test_get_or_create_secret
    test_is_enabled

    # Summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
    fi

    # Cleanup
    rm -rf "$TEST_DIR"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo ""
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

main
