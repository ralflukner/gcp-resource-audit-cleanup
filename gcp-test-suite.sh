#!/opt/homebrew/bin/bash
#
# Enhanced Test Suite for GCP Resource Management System
# Version: 3.2.7-test
# Author: Ralf B Lukner MD PhD
#
# This test suite provides comprehensive validation of the GCP Resource Management System.
# It implements a systematic approach to testing, similar to how we validate medical
# protocols or engineering systems - through rigorous, repeatable test procedures
# with clear pass/fail criteria and detailed logging of results.
#
# Core Testing Philosophy:
# - Each test should be independent and idempotent
# - All tests must clean up after themselves
# - Failures should be clearly documented with context
# - Tests should validate both happy paths and error conditions
# - Cross-platform compatibility must be maintained
#
# The testing approach mirrors clinical trial methodology:
# - Clear hypothesis (expected behavior)
# - Controlled environment (isolated test conditions)
# - Measurable outcomes (explicit pass/fail criteria)
# - Detailed documentation (comprehensive logging)
# - Statistical validity (multiple test runs)

# --- Shell Settings for Strict Mode ---
# These settings help catch common shell scripting errors early:
# errexit: Exit on any error
# nounset: Error on undefined variables
# pipefail: If any command in a pipe fails, the pipe fails
set -o errexit
set -o nounset
set -o pipefail

# --- Test Configuration ---
# Note: These declarations must come before sourcing gcp-utils.sh
# to prevent conflicts with readonly variables there
declare -r TEST_SUITE_VERSION="3.2.7-test"
declare -r TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r TEST_OUTPUT_DIR="./test_output"
declare -r TEST_DATA_DIR="${TEST_SCRIPT_DIR}/test_data"

# Import core utilities - this gives us access to all the core functionality
# that we need to test
source "${TEST_SCRIPT_DIR}/gcp-utils.sh"

# --- Cross-Platform Date Handling ---

get_current_timestamp() {
    # Provides consistent timestamp format across different operating systems
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        date -u "+%Y-%m-%dT%H:%M:%SZ"
    else
        # Linux version
        date -u "+%Y-%m-%dT%H:%M:%SZ"
    fi
}

get_date_ago() {
    local days_ago="$1"
    # Handles date arithmetic consistently across platforms
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        date -v-"${days_ago}"d -u "+%Y-%m-%dT%H:%M:%SZ"
    else
        # Linux version
        date -d "${days_ago} days ago" -u "+%Y-%m-%dT%H:%M:%SZ"
    fi
}

format_timestamp() {
    local unix_timestamp="$1"
    # Converts Unix timestamps to ISO 8601 format
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        date -r "$unix_timestamp" -u "+%Y-%m-%dT%H:%M:%SZ"
    else
        # Linux version
        date -d "@$unix_timestamp" -u "+%Y-%m-%dT%H:%M:%SZ"
    fi
}

# --- Mock Data Generation ---

generate_mock_compute_metrics() {
    local instance_name="$1"
    local days_back="$2"
    
    # We generate realistic CPU utilization patterns that match common scenarios:
    # - Underutilized resources (potential cost optimization)
    # - Spiky utilization (potential scaling issues)
    # - Normal utilization (baseline comparison)
    local current_time=$(date +%s)
    local metrics=()
    
    # Generate data points with different patterns
    for ((i=0; i<days_back*24; i++)); do
        local timestamp=$((current_time - i*3600))
        local formatted_time
        formatted_time=$(format_timestamp "${timestamp}")
        local value
        
        # Each instance type gets a distinct utilization pattern that represents
        # a specific real-world scenario we want to test
        case "$instance_name" in
            "test-instance-underutilized")
                # Simulates an oversized or unnecessary instance
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()*0.2}')
                ;;
            "test-instance-spiky")
                # Simulates a poorly sized or misconfigured instance
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()}')
                ;;
            "test-instance-normal")
                # Simulates a well-configured instance
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print 0.4 + rand()*0.2}')
                ;;
            *)
                # Default pattern for unexpected cases
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()*0.5}')
                ;;
        esac
        
        metrics+=("{\"timestamp\": \"${formatted_time}\", \"value\": ${value}}")
    done
    
    # Return metrics in JSON format matching API response structure
    printf '{"metrics": [\n%s\n]}' "$(IFS=,; echo "${metrics[*]}")"
}

# --- Enhanced Error Handling Tests ---

test_error_handling() {
    log "INFO" "Testing enhanced error handling functionality"
    
    # We test each error category independently to ensure proper handling
    # of different types of failures that can occur in production
    
    # Network connectivity issues
    test_network_error_handling || return 1
    
    # API rate limiting
    test_rate_limit_handling || return 1
    
    # Resource quota management
    test_quota_exceeded_handling || return 1
    
    # Permission and security boundaries
    test_permission_boundary_handling || return 1
    
    # Data integrity and corruption
    test_state_corruption_handling || return 1
    
    # Resource contention and deadlocks
    test_deadlock_handling || return 1
    
    return 0
}

test_network_error_handling() {
    log "INFO" "Testing network error handling"
    
    # Simulate network failure
    export SIMULATE_NETWORK_ERROR=true
    
    # Attempt operation that requires network access
    if analyze_compute_resources "test-project" "test-data.json" "output.json" 2>/dev/null; then
        log "ERROR" "Network error handling failed - operation succeeded when it should have failed"
        return 1
    fi
    
    # Verify error response
    if [[ $? -ne ${E_NETWORK_ERROR} ]]; then
        log "ERROR" "Incorrect error code returned for network error"
        return 1
    fi
    
    unset SIMULATE_NETWORK_ERROR
    return 0
}

# --- State Management Tests ---

test_state_management() {
    log "INFO" "Testing state management functionality"
    
    # Test state backup systems
    test_state_backup || return 1
    
    # Test corruption detection
    test_state_corruption_detection || return 1
    
    # Test recovery mechanisms
    test_state_recovery || return 1
    
    # Test validation systems
    test_state_validation || return 1
    
    return 0
}

test_state_backup() {
    log "INFO" "Testing state backup functionality"
    
    # Create test state that represents a typical resource configuration
    local test_state='{"resources":{"test-resource":"active"}}'
    echo "${test_state}" > "${STATE_DIR}/current_state.json"
    
    # Attempt state modification
    if ! update_resource_state "test-resource" "inactive"; then
        log "ERROR" "State update failed"
        return 1
    fi
    
    # Verify backup creation and integrity
    local backup_count
    backup_count=$(find "${BACKUP_DIR}" -name "state_*.json" | wc -l)
    if (( backup_count != 1 )); then
        log "ERROR" "Expected 1 backup file, found ${backup_count}"
        return 1
    fi
    
    return 0
}

# --- Resource Locking Tests ---

test_resource_locking() {
    log "INFO" "Testing resource locking functionality"
    
    # Test lock acquisition and release
    test_lock_acquisition || return 1
    
    # Test timeout handling
    test_lock_timeout || return 1
    
    # Test deadlock prevention
    test_deadlock_detection || return 1
    
    # Test lock inheritance
    test_lock_inheritance || return 1
    
    return 0
}

test_lock_acquisition() {
    log "INFO" "Testing lock acquisition"
    
    local test_resource="test-resource-$$"
    
    # Attempt to acquire lock
    if ! acquire_resource_lock "${test_resource}"; then
        log "ERROR" "Failed to acquire initial lock"
        return 1
    fi
    
    # Verify lock file creation
    if [[ ! -d "${LOCK_DIR}/${test_resource}.lock" ]]; then
        log "ERROR" "Lock directory not created"
        return 1
    fi
    
    # Verify lock registry
    if ! jq -e ".locks[\"${test_resource}\"]" "${LOCK_DIR}/lock_registry.json" >/dev/null; then
        log "ERROR" "Lock not recorded in registry"
        return 1
    fi
    
    # Clean up
    release_resource_lock "${test_resource}"
    
    return 0
}

# --- Audit Trail Tests ---

test_audit_trail() {
    log "INFO" "Testing audit trail functionality"
    
    # Test audit record creation
    test_audit_entry_creation || return 1
    
    # Test audit data integrity
    test_audit_integrity || return 1
    
    return 0
}

test_audit_entry_creation() {
    log "INFO" "Testing audit entry creation"
    
    local test_operation="test-operation"
    local test_resource="test-resource-$$"
    
    # Create audit record
    if ! create_audit_entry "${test_operation}" "${test_resource}"; then
        log "ERROR" "Failed to create audit entry"
        return 1
    fi
    
    # Verify audit record
    local entry_count
    entry_count=$(jq ".audit_entries | length" "${LOG_DIR}/audit_trail.json")
    if (( entry_count != 1 )); then
        log "ERROR" "Expected 1 audit entry, found ${entry_count}"
        return 1
    fi
    
    return 0
}

# --- Cross-Platform Tests ---

test_cross_platform_compatibility() {
    log "INFO" "Testing cross-platform compatibility"
    
    # Test date operations
    test_date_handling || return 1
    
    # Test file systems
    test_file_permissions || return 1
    
    # Test path handling
    test_path_handling || return 1
    
    return 0
}

test_date_handling() {
    log "INFO" "Testing cross-platform date handling"
    
    # Test UTC timestamp generation
    local timestamp
    timestamp=$(get_current_timestamp)
    if [[ ! "${timestamp}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        log "ERROR" "Invalid timestamp format: ${timestamp}"
        return 1
    fi
    
    # Test date arithmetic
    local past_date
    past_date=$(get_date_ago 7)
    if [[ ! "${past_date}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        log "ERROR" "Invalid past date format: ${past_date}"
        return 1
    fi
    
    return 0
}

# --- Test Environment Setup ---

setup_test_environment() {
    log "INFO" "Setting up test environment"
    
    # Create temporary test directories
    if ! TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gcp-test.XXXXXXXXXX"); then
        log "ERROR" "Failed to create temporary test directory"
        return 1
    fi
    
    # Create required directory structure
    local -a required_dirs=(
        "${TEMP_DIR}/mock/compute"
        "${TEMP_DIR}/mock/storage"
        "${TEMP_DIR}/mock/network"
        "${TEMP_DIR}/output"
        "${TEMP_DIR}/logs"
    )
    
    for dir in "${required_dirs[@]}"; do
        if ! mkdir -p "${dir}"; then
            log "ERROR" "Failed to create directory: ${dir}"
            cleanup_test_environment
            return 1
        fi
    done
    
    return 0
}

cleanup_test_environment() {
    log "INFO" "Cleaning up test environment"
    rm -rf "${TEMP_DIR}"
}

# --- Main Test Runner ---

run_test_suite() {
    log "INFO" "Starting test suite version ${TEST_SUITE_VERSION}"
    
    local -a test_groups=(
        "error_handling"
        "state_management"
        "resource_locking"
        "audit_trail"
        "cross_platform_compatibility"
    )
    
    local failed_tests=0
    
    # Execute each test group
    for group in "${test_groups[@]}"; do
        log "INFO" "Running test group: ${group}"
        if ! "test_${group}"; then
            log "ERROR" "Test group failed: ${group}"
            ((failed_tests++))
        fi
    done
    
    # Generate final report
    generate_test_report "${failed_tests}"
    
    return ${failed_tests}
}

# --- Command Line Processing ---

process_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-all)
                RUN_ALL_TESTS=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    --run-all    Run all tests
    --help       Show this help message

Example:
    $(basename "$0") --run-all
EOF
}

# --- Main Entry Point ---

main() {
    local RUN_ALL_TESTS=false
    
    # Process command line arguments
    process_arguments "$@"
    
    # Initialize test environment
    initialize_test_environment || exit 1
    
    # Run tests
    if [[ "${RUN_ALL_TESTS}" == true ]]; then
        run_test_suite
    else
        run_selected_tests "$@"
    fi
    
    # Cleanup
    cleanup_test_environment
    
    return 0
}

# Execute if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi