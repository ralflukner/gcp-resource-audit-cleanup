#!/bin/bash
#
# Comprehensive Test Suite for GCP Resource Management System
# Version: 3.2.6-test
# Author: Ralf B Lukner MD PhD
#
# This test suite provides thorough validation of all core functionality
# in the GCP Resource Management System, with particular focus on:
# - Resource analysis accuracy
# - Error handling robustness
# - Input validation completeness
# - Integration point verification
# - Resource cleanup validation

# --- Global Constants ---
readonly SCRIPT_VERSION="3.2.6-test"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MAIN_SCRIPT="${SCRIPT_DIR}/resource-analysis.sh"
readonly OUTPUT_SCRIPT="${SCRIPT_DIR}/resource-analysis-output.sh"

# --- Test Environment Setup ---

setup_test_environment() {
    log "INFO" "Setting up isolated test environment"
    
    # Create temporary test directory with proper cleanup
    if ! TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gcp-test.XXXXXXXXXX"); then
        log "ERROR" "Failed to create temporary test directory"
        return 1
    fi
    
    # Create mock data directory structure
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
    
    # Initialize mock data
    if ! setup_mock_data; then
        log "ERROR" "Failed to initialize mock data"
        cleanup_test_environment
        return 1
    fi
    
    return 0
}

setup_mock_data() {
    # Create mock compute instance data
    cat > "${TEMP_DIR}/mock/compute/instances.json" << 'EOF'
[
    {
        "name": "test-instance-1",
        "zone": "us-central1-a",
        "machineType": "n1-standard-2",
        "status": "RUNNING",
        "metrics": {
            "cpu_utilization": 0.75,
            "memory_utilization": 0.82
        }
    },
    {
        "name": "test-instance-2",
        "zone": "us-central1-b",
        "machineType": "n1-standard-1",
        "status": "RUNNING",
        "metrics": {
            "cpu_utilization": 0.15,
            "memory_utilization": 0.22
        }
    }
]
EOF

    # Create mock storage data
    cat > "${TEMP_DIR}/mock/storage/buckets.json" << 'EOF'
[
    {
        "name": "test-bucket-1",
        "location": "US",
        "storageClass": "STANDARD",
        "size_bytes": 1073741824,
        "last_access": "2024-01-20"
    },
    {
        "name": "test-bucket-2",
        "location": "US",
        "storageClass": "NEARLINE",
        "size_bytes": 2147483648,
        "last_access": "2023-12-15"
    }
]
EOF

    return 0
}

# --- Test Functions ---

test_resource_analysis() {
    log "INFO" "Testing resource analysis functionality"
    
    # Test compute resource analysis
    if ! test_compute_analysis; then
        log "ERROR" "Compute resource analysis test failed"
        return 1
    fi
    
    # Test storage resource analysis
    if ! test_storage_analysis; then
        log "ERROR" "Storage resource analysis test failed"
        return 1
    fi
    
    # Test output formatting
    if ! test_output_formatting; then
        log "ERROR" "Output formatting test failed"
        return 1
    fi
    
    return 0
}

test_compute_analysis() {
    local test_data="${TEMP_DIR}/mock/compute/instances.json"
    local output_file="${TEMP_DIR}/output/compute_analysis.json"
    
    # Run analysis
    if ! analyze_compute_resources "test-project" "${test_data}" "${output_file}"; then
        return 1
    fi
    
    # Verify analysis results
    if ! verify_compute_analysis "${output_file}"; then
        return 1
    fi
    
    return 0
}

verify_compute_analysis() {
    local analysis_file="$1"
    
    # Verify file exists and is valid JSON
    if [[ ! -f "${analysis_file}" ]] || ! jq empty "${analysis_file}" 2>/dev/null; then
        log "ERROR" "Invalid analysis output file"
        return 1
    fi
    
    # Verify required analysis components
    local required_fields=(
        ".resources.compute"
        ".patterns.usage"
        ".recommendations"
    )
    
    for field in "${required_fields[@]}"; do
        if ! jq -e "${field}" "${analysis_file}" >/dev/null; then
            log "ERROR" "Missing required field: ${field}"
            return 1
        fi
    done
    
    # Verify specific analysis logic
    if ! verify_utilization_patterns "${analysis_file}"; then
        return 1
    fi
    
    return 0
}

verify_utilization_patterns() {
    local analysis_file="$1"
    
    # Get analysis results for test-instance-2 (known underutilized)
    local instance_pattern
    instance_pattern=$(jq -r '.resources.compute[] | 
        select(.name == "test-instance-2") | 
        .patterns.cpu_pattern' "${analysis_file}")
    
    # Verify pattern detection
    if [[ "${instance_pattern}" != "underutilized" ]]; then
        log "ERROR" "Failed to detect underutilized pattern"
        return 1
    fi
    
    return 0
}

test_storage_analysis() {
    local test_data="${TEMP_DIR}/mock/storage/buckets.json"
    local output_file="${TEMP_DIR}/output/storage_analysis.json"
    
    # Run analysis
    if ! analyze_storage_resources "test-project" "${test_data}" "${output_file}"; then
        return 1
    fi
    
    # Verify analysis results
    if ! verify_storage_analysis "${output_file}"; then
        return 1
    fi
    
    return 0
}

verify_storage_analysis() {
    local analysis_file="$1"
    
    # Verify storage class recommendations
    local nearline_bucket
    nearline_bucket=$(jq -r '.resources.storage[] | 
        select(.name == "test-bucket-2")' "${analysis_file}")
    
    if [[ -z "${nearline_bucket}" ]]; then
        log "ERROR" "Failed to analyze Nearline storage bucket"
        return 1
    fi
    
    return 0
}

test_output_formatting() {
    local test_data="${TEMP_DIR}/mock/compute/instances.json"
    local analysis_file="${TEMP_DIR}/output/analysis.json"
    local formatted_output="${TEMP_DIR}/output/formatted_report.txt"
    
    # Generate analysis output
    if ! analyze_resources "test-project" "${test_data}" "${analysis_file}"; then
        return 1
    fi
    
    # Format output
    if ! format_resource_report "${analysis_file}" "${formatted_output}"; then
        return 1
    fi
    
    # Verify formatted output
    if ! verify_formatted_output "${formatted_output}"; then
        return 1
    fi
    
    return 0
}

verify_formatted_output() {
    local output_file="$1"
    
    # Verify file exists and has content
    if [[ ! -f "${output_file}" ]] || [[ ! -s "${output_file}" ]]; then
        log "ERROR" "Missing or empty formatted output"
        return 1
    fi
    
    # Verify required sections
    local required_sections=(
        "COMPUTE RESOURCE UTILIZATION"
        "STORAGE RESOURCE UTILIZATION"
        "OPTIMIZATION RECOMMENDATIONS"
    )
    
    for section in "${required_sections[@]}"; do
        if ! grep -q "${section}" "${output_file}"; then
            log "ERROR" "Missing required section: ${section}"
            return 1
        fi
    done
    
    return 0
}

# --- Error Handling Tests ---

test_error_handling() {
    log "INFO" "Testing error handling functionality"
    
    # Test invalid input handling
    if ! test_invalid_input_handling; then
        log "ERROR" "Invalid input handling test failed"
        return 1
    fi
    
    # Test API error handling
    if ! test_api_error_handling; then
        log "ERROR" "API error handling test failed"
        return 1
    fi
    
    # Test resource cleanup on error
    if ! test_cleanup_on_error; then
        log "ERROR" "Cleanup on error test failed"
        return 1
    fi
    
    return 0
}

# --- Integration Tests ---

test_integration() {
    log "INFO" "Running integration tests"
    
    # Test end-to-end analysis workflow
    if ! test_analysis_workflow; then
        log "ERROR" "Analysis workflow test failed"
        return 1
    fi
    
    # Test menu system integration
    if ! test_menu_integration; then
        log "ERROR" "Menu integration test failed"
        return 1
    fi
    
    return 0
}

# --- Main Test Runner ---

run_test_suite() {
    local -a test_groups=(
        "resource_analysis"
        "error_handling"
        "integration"
    )
    
    local failed_tests=0
    
    for group in "${test_groups[@]}"; do
        log "INFO" "Running test group: ${group}"
        if ! "test_${group}"; then
            ((failed_tests++))
        fi
    done
    
    # Generate test report
    generate_test_report
    
    return ${failed_tests}
}

# --- Main Entry Point ---

main() {
    # Setup test environment
    if ! setup_test_environment; then
        log "ERROR" "Failed to setup test environment"
        exit 1
    fi
    
    # Run test suite
    if ! run_test_suite; then
        log "ERROR" "Test suite failed"
        cleanup_test_environment
        exit 1
    fi
    
    # Cleanup
    cleanup_test_environment
    
    log "INFO" "Test suite completed successfully"
    return 0
}

# Execute if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
