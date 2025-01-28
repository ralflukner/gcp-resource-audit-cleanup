# --- Test Suite for GCP Resource Management Utilities ---

# Test runner function
run_tests() {
    local test_results=()
    local failed_tests=0
    
    log "INFO" "Starting test suite execution"
    
    # Run all test functions
    for test_function in $(declare -F | grep "test_" | cut -d" " -f3); do
        log "DEBUG" "Running test: ${test_function}"
        
        if ${test_function}; then
            test_results+=("✓ ${test_function}")
        else
            test_results+=("✗ ${test_function}")
            ((failed_tests++))
        fi
    done
    
    # Print test results
    echo -e "\nTest Results:"
    printf "%s\n" "${test_results[@]}"
    echo -e "\nTests completed: ${#test_results[@]}, Failed: ${failed_tests}"
    
    return ${failed_tests}
}

# Test backoff implementation
test_backoff_implementation() {
    local test_attempts=3
    local start_time=$(date +%s)
    
    # Test increasing wait times
    for ((i=0; i<test_attempts; i++)); do
        implement_backoff $i $test_attempts
        local result=$?
        
        if [[ ${result} -ne 0 && ${i} -lt $((test_attempts-1)) ]]; then
            return 1
        fi
    done
    
    # Verify that backoff actually waited
    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    if [[ ${elapsed} -lt 3 ]]; then
        log "ERROR" "Backoff didn't wait long enough: ${elapsed}s"
        return 1
    fi
    
    return 0
}

# Test resource name validation
test_resource_name_validation() {
    # Test valid names
    local valid_names=(
        "my-instance-1"
        "test-disk-2"
        "snapshot-backup-3"
    )
    
    # Test invalid names
    local invalid_names=(
        "My_Invalid_Instance"
        "test@disk"
        "snapshot.backup"
    )
    
    # Test valid names
    for name in "${valid_names[@]}"; do
        if ! validate_resource_name "${name}" "instance"; then
            log "ERROR" "Valid name failed validation: ${name}"
            return 1
        fi
    done
    
    # Test invalid names
    for name in "${invalid_names[@]}"; do
        if validate_resource_name "${name}" "instance"; then
            log "ERROR" "Invalid name passed validation: ${name}"
            return 1
        fi
    done
    
    return 0
}

# Test resource locking mechanism
test_resource_locking() {
    local test_resource="test-resource-$$"
    
    # Test lock acquisition
    if ! acquire_resource_lock "${test_resource}"; then
        log "ERROR" "Failed to acquire initial lock"
        return 1
    fi
    
    # Test duplicate lock acquisition (should fail)
    if acquire_resource_lock "${test_resource}" 2>/dev/null; then
        log "ERROR" "Successfully acquired duplicate lock"
        release_resource_lock "${test_resource}"
        return 1
    fi
    
    # Test lock release
    if ! release_resource_lock "${test_resource}"; then
        log "ERROR" "Failed to release lock"
        return 1
    fi
    
    # Test release of non-existent lock
    if release_resource_lock "nonexistent-resource-$$" 2>/dev/null; then
        log "ERROR" "Successfully released non-existent lock"
        return 1
    fi
    
    return 0
}

# Test dependency graph building
test_dependency_graph() {
    local test_instance="test-instance-$$"
    local graph_file="${TEMP_DIR}/dependency_graph.json"
    
    # Create mock instance data
    mkdir -p "${TEMP_DIR}/mock"
    cat > "${TEMP_DIR}/mock/instance.json" << EOF
{
    "name": "${test_instance}",
    "disks": [
        {"source": "projects/test-project/zones/us-central1-a/disks/test-disk-1"},
        {"source": "projects/test-project/zones/us-central1-a/disks/test-disk-2"}
    ]
}
EOF
    
    # Mock gcloud command for testing
    function gcloud() {
        if [[ "$*" =~ "compute instances describe" ]]; then
            cat "${TEMP_DIR}/mock/instance.json"
            return 0
        fi
        return 1
    }
    
    # Build dependency graph
    if ! build_dependency_graph "instances" "${test_instance}"; then
        log "ERROR" "Failed to build dependency graph"
        return 1
    fi
    
    # Verify graph structure
    if ! jq -e '.nodes | length == 1' "${graph_file}" >/dev/null; then
        log "ERROR" "Incorrect number of nodes in graph"
        return 1
    fi
    
    if ! jq -e '.edges | length == 2' "${graph_file}" >/dev/null; then
        log "ERROR" "Incorrect number of edges in graph"
        return 1
    fi
    
    return 0
}

# Integration test for all components
test_integration() {
    local test_resource="integration-test-$$"
    
    # Test complete workflow
    if ! validate_resource_name "${test_resource}" "instance" || \
       ! acquire_resource_lock "${test_resource}" || \
       ! build_dependency_graph "instances" "${test_resource}" || \
       ! release_resource_lock "${test_resource}"; then
        log "ERROR" "Integration test failed"
        return 1
    fi
    
    return 0
}

# Main test execution
main() {
    # Setup test environment
    local original_temp_dir="${TEMP_DIR}"
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gcp-test.XXXXXXXXXX")
    
    # Run tests
    run_tests
    local test_result=$?
    
    # Cleanup
    rm -rf "${TEMP_DIR}"