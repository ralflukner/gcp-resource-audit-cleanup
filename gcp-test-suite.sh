# Enhanced Test Suite for Resource Analysis Components
# File: gcp-test-suite.sh
# Version: 1.0.0
# Author: Ralf B Lukner MD PhD

# Import core utilities
source "${SCRIPT_DIR}/gcp-utils.sh"

# --- Test Suite Configuration ---
readonly TEST_VERSION="1.0.0"
readonly TEST_OUTPUT_DIR="${TEMP_DIR}/test_output"
readonly TEST_DATA_DIR="${SCRIPT_DIR}/test_data"

# --- Mock Data Generation ---

generate_mock_compute_metrics() {
    local instance_name="$1"
    local days_back="$2"
    
    # Generate realistic CPU utilization patterns
    local current_time=$(date +%s)
    local metrics=()
    
    # Generate data points with different patterns
    for ((i=0; i<days_back*24; i++)); do
        local timestamp=$((current_time - i*3600))
        local value
        
        # Create different utilization patterns
        case "$instance_name" in
            "test-instance-underutilized")
                # Consistently low utilization (0-20%)
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()*0.2}')
                ;;
            "test-instance-spiky")
                # Highly variable utilization (0-100%)
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()}')
                ;;
            "test-instance-normal")
                # Moderate utilization (40-60%)
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print 0.4 + rand()*0.2}')
                ;;
            *)
                value=$(awk -v seed=$RANDOM 'BEGIN{srand(seed); print rand()*0.5}')
                ;;
        esac
        
        metrics+=("{\"timestamp\": \"$(date -u -d @${timestamp} +"%Y-%m-%dT%H:%M:%SZ")\", \"value\": ${value}}")
    done
    
    # Return JSON array of metrics
    printf '{"metrics": [\n%s\n]}' "$(IFS=,; echo "${metrics[*]}")"
}

# --- Test Cases ---

test_resource_analysis() {
    log "INFO" "Testing resource analysis functionality"
    
    # Generate test data
    local test_data_file="${TEST_OUTPUT_DIR}/test_metrics.json"
    mkdir -p "${TEST_OUTPUT_DIR}"
    
    # Test different utilization patterns
    local -a test_instances=(
        "test-instance-underutilized"
        "test-instance-spiky"
        "test-instance-normal"
    )
    
    local failed_tests=0
    
    for instance in "${test_instances[@]}"; do
        log "INFO" "Testing analysis for ${instance}"
        
        # Generate mock metrics
        generate_mock_compute_metrics "${instance}" 7 > "${test_data_file}"
        
        # Run analysis
        local analysis_output="${TEST_OUTPUT_DIR}/${instance}_analysis.json"
        if ! analyze_resource_patterns "test-project" "${instance}" "${test_data_file}" "${analysis_output}"; then
            log "ERROR" "Analysis failed for ${instance}"
            ((failed_tests++))
            continue
        fi
        
        # Verify analysis results
        if ! verify_analysis_results "${instance}" "${analysis_output}"; then
            log "ERROR" "Analysis verification failed for ${instance}"
            ((failed_tests++))
            continue
        fi
        
        log "INFO" "Analysis test passed for ${instance}"
    done
    
    return ${failed_tests}
}

verify_analysis_results() {
    local instance_name="$1"
    local analysis_file="$2"
    
    # Verify file exists and is valid JSON
    if [[ ! -f "${analysis_file}" ]] || ! jq empty "${analysis_file}" 2>/dev/null; then
        log "ERROR" "Invalid analysis output file: ${analysis_file}"
        return 1
    fi
    
    # Verify expected pattern detection
    local expected_pattern
    case "${instance_name}" in
        "test-instance-underutilized")
            expected_pattern="underutilized"
            ;;
        "test-instance-spiky")
            expected_pattern="spiky"
            ;;
        "test-instance-normal")
            expected_pattern="normal"
            ;;
        *)
            log "ERROR" "Unknown test instance: ${instance_name}"
            return 1
            ;;
    esac
    
    local detected_pattern
    detected_pattern=$(jq -r '.patterns.compute[0].usage_patterns.cpu_pattern.pattern' "${analysis_file}")
    
    if [[ "${detected_pattern}" != "${expected_pattern}" ]]; then
        log "ERROR" "Pattern detection failed for ${instance_name}. Expected: ${expected_pattern}, Got: ${detected_pattern}"
        return 1
    fi
    
    # Verify recommendations exist
    if ! jq -e '.recommendations | length > 0' "${analysis_file}" >/dev/null; then
        log "ERROR" "No recommendations generated for ${instance_name}"
        return 1
    fi
    
    return 0
}

# --- Integration Tests ---

test_integration() {
    log "INFO" "Running integration tests"
    
    # Test end-to-end workflow
    local project_id="test-project-$$"
    local output_dir="${TEST_OUTPUT_DIR}/integration"
    mkdir -p "${output_dir}"
    
    # Setup test environment
    if ! setup_test_environment "${project_id}" "${output_dir}"; then
        log "ERROR" "Failed to setup test environment"
        return 1
    fi
    
    # Run analysis workflow
    if ! run_analysis_workflow "${project_id}" "${output_dir}"; then
        log "ERROR" "Analysis workflow failed"
        cleanup_test_environment
        return 1
    fi
    
    # Verify results
    if ! verify_workflow_results "${output_dir}"; then
        log "ERROR" "Workflow verification failed"
        cleanup_test_environment
        return 1
    fi
    
    # Cleanup
    cleanup_test_environment
    
    log "INFO" "Integration tests completed successfully"
    return 0
}

# --- Main Test Runner ---

run_test_suite() {
    log "INFO" "Starting test suite execution"
    
    local failed_tests=0
    
    # Run unit tests
    if ! test_resource_analysis; then
        ((failed_tests++))
    fi
    
    # Run integration tests
    if ! test_integration; then
        ((failed_tests++))
    fi
    
    # Generate test report
    generate_test_report
    
    return ${failed_tests}
}

# Execute if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_test_suite
fi