#!/opt/homebrew/bin/bash
#
# GCP Test Suite Main Runner
# Version: 3.2.7
# Author: Ralf B Lukner MD PhD
#
# This implementation follows a medical diagnostic approach:
# - Initial assessment (environment setup)
# - Systematic testing (like running diagnostic tests)
# - Progress monitoring (like patient vital signs)
# - Results reporting (like a medical report)
#
# The test framework is organized like a medical diagnostic protocol:
# 1. Initial Setup (like preparing an exam room)
# 2. Environment Validation (like checking equipment)
# 3. Test Execution (like running diagnostics)
# 4. Result Analysis (like interpreting results)
# 5. Report Generation (like creating medical reports)
# 6. Cleanup Procedures (like room turnover)

# --- Shell Settings ---
set -o errexit   # Exit on error (like stopping on adverse events)
set -o nounset   # Error on undefined variables (like checking all parameters)
set -o pipefail  # Exit on pipe failures (like monitoring all steps)

# --- Constants ---
# First declare all constants
declare TEST_SUITE_VERSION
declare TEST_SCRIPT_DIR
declare TEST_DATA_DIR
declare TEST_OUTPUT_DIR
declare PROCESS_PATTERN="[g]cp-"  # Pattern for finding our processes

# Then assign values (separated to avoid masking return values)
TEST_SUITE_VERSION="3.2.7"
TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DATA_DIR="${TEST_SCRIPT_DIR}/test_data"
TEST_OUTPUT_DIR="./test_output"

# Export needed variables
export TEST_DATA_DIR
export TEST_OUTPUT_DIR

# Global variables (mutable)
TEMP_DIR=""  # Will be set during initialization (like temporary exam room)

# Source utilities (like loading medical equipment)
source "${TEST_SCRIPT_DIR}/gcp-utils.sh"

# --- Process Management ---
find_test_processes() {
    # Use pgrep instead of grepping ps output
    # This is more reliable for process identification
    local pids
    if command -v pgrep >/dev/null 2>&1; then
        pids=$(pgrep -f "${PROCESS_PATTERN}" || true)
    else
        # Fallback if pgrep isn't available
        pids=$(ps -ef | awk -v pat="${PROCESS_PATTERN}" '$0 ~ pat {print $2}')
    fi
    echo "${pids}"
}

# --- Cross-Platform Timeout Implementation ---
run_with_timeout() {
    local timeout_duration="$1"
    local test_name="$2"  # Add test name as the second argument
    shift 2
    local command=("$@")

    # Start command in background
    "${command[@]}" &
    local command_pid=$!

    # Set timer in background
    (
        sleep "${timeout_duration}"
        if kill -0 ${command_pid} 2>/dev/null; then
            kill -TERM ${command_pid} 2>/dev/null
            sleep 1
            kill -KILL ${command_pid} 2>/dev/null
        fi
    ) &
    local timer_pid=$!

    # Wait for command to complete
    wait ${command_pid} 2>/dev/null
    local command_status=$?

    # Clean up timer if command finished before timeout
    kill -TERM ${timer_pid} 2>/dev/null

    # Call capture_test_diagnostics if the command fails
    if [[ ${command_status} -ne 0 ]]; then
        capture_test_diagnostics "${test_name}"  # Pass the test name as an argument
    fi

    return ${command_status}
}

# --- Progress Tracking ---
# Monitors test execution like vital signs monitoring
track_progress() {
    local stage="$1"    # Current stage of testing (like phase of exam)
    local status="$2"   # Status indicator (like vital sign reading)
    local detail="${3:-}"  # Additional information (like clinical notes)
    
    # Format timestamp for consistent logging (like time stamps on readings)
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log progress with clear stage indication
    printf "[%s] [%-10s] %-20s %s\n" \
        "${timestamp}" \
        "${stage}" \
        "${status}" \
        "${detail}"
}

# --- Test Environment Setup ---
# Prepares test environment like setting up an exam room
# --- Test Environment Setup ---
initialize_test_environment() {
    track_progress "SETUP" "Starting" "Environment initialization"

    # Create temporary directory with proper error handling
    local temp_dir
    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gcp-test.$(date +%Y%m%d).XXXXXX")

    if [[ ! -d "${temp_dir}" ]]; then
        track_progress "SETUP" "Failed" "Could not create temp directory"
        return 1
    fi

    # Assign to global variable after successful creation
    TEMP_DIR="${temp_dir}"
    track_progress "SETUP" "Created" "Temporary directory: ${TEMP_DIR}"

    return 0
}

# --- Test State Management ---
# Manages test state like maintaining patient records
initialize_test_state() {
    local state_file="${TEMP_DIR}/test_state.json"
    track_progress "STATE" "Starting" "Initializing test state"
    
    # Create initial state file (like creating patient chart)
    cat > "${state_file}" << EOF

# Initialize test state with proper JSON formatting and error checking
initialize_test_state() {
    local state_file="${TEMP_DIR}/test_state.json"
    track_progress "STATE" "Starting" "Initializing test state"

    # First get timestamp with error checking
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ") || {
        track_progress "ERROR" "Failed" "Could not generate timestamp"
        return 1
    }

    # Generate unique run ID with fallback
    local run_id
    run_id=$(uuidgen 2>/dev/null || echo "test-${RANDOM}")

    # Create properly formatted JSON state
    # Note the careful indentation and lack of leading spaces
    cat > "${state_file}" << EOF || return 1
{
    "timestamp": "${timestamp}",
    "test_run_id": "$(uuidgen 2>/dev/null || echo "test-${RANDOM}")",
    "environment": {
        "os": "${OSTYPE}",
        "shell_version": "${BASH_VERSION}",
        "test_suite_version": "${TEST_SUITE_VERSION}"
    },
    "results": {
        "passed": 0,
        "failed": 0,
        "skipped": 0
    }
}
EOF

    # Verify JSON is valid
    if ! jq empty "${state_file}" 2>/dev/null; then
        track_progress "ERROR" "Failed" "Invalid JSON state file"
        return 1
    fi

    # Set proper permissions
    chmod 0640 "${state_file}"
    
    track_progress "STATE" "Complete" "Test state initialized"
    return 0
}

# --- Diagnostic Functions ---
# Captures detailed diagnostic information for test failures
capture_test_diagnostics() {
    local test_name
    if [[ -z "${1:-}" ]]; then
        log "ERROR" "Test name is required for capturing diagnostics"
        log "DEBUG" "Call stack:"
        local frame=0
        while caller $frame; do
            ((frame++))
        done
        return 1
    else
        test_name="$1"
    fi
    local timestamp
    timestamp=$(date -u +"%Y%m%d_%H%M%S")
    local diagnostic_dir="${TEST_OUTPUT_DIR}/diagnostics/${test_name}_${timestamp}"

    track_progress "DIAG" "Starting" "Capturing diagnostics for ${test_name}"

    # Create diagnostic directory
    mkdir -p "${diagnostic_dir}"

    # Capture system state (like vital signs)
    {
        echo "=== System State ==="
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Memory Usage:"
        free -h 2>/dev/null || vm_stat 2>/dev/null || echo "Memory stats unavailable"
        echo
        echo "Process State:"
        pgrep -f "gcp-" >/dev/null || echo "Process info unavailable"
        echo
        echo "Resource Usage:"
        top -l 1 -n 0 2>/dev/null || top -n 1 -b 2>/dev/null || echo "Resource usage unavailable"
    } > "${diagnostic_dir}/system_state.txt"

    # Capture test environment (like patient history)
    {
        echo "=== Test Environment ==="
        echo "Test Suite Version: ${TEST_SUITE_VERSION}"
        echo "Operating System: ${OSTYPE}"
        echo "Shell Version: ${BASH_VERSION}"
        echo "Working Directory: $(pwd)"
        echo
        echo "Environment Variables:"
        env | grep -E "^(GCP_|TEST_|PATH)"
        echo
        echo "Directory Structure:"
        find "${TEST_OUTPUT_DIR}" -type d
    } > "${diagnostic_dir}/test_environment.txt"

    # Capture recent logs (like recent symptoms)
    {
        echo "=== Recent Log Entries ==="
        if [[ -f "${TEST_OUTPUT_DIR}/test.log" ]]; then
            tail -n 100 "${TEST_OUTPUT_DIR}/test.log"
        else
            echo "No test log file found"
        fi
    } > "${diagnostic_dir}/recent_logs.txt"

    # Capture stack trace (like diagnostic chain)
    {
        echo "=== Stack Trace ==="
        echo "Error occurred in test: ${test_name}"
        local frame=0
        while caller $frame; do
            ((frame++))
        done
    } > "${diagnostic_dir}/stack_trace.txt"

    # Generate diagnostic summary (like medical report)
    generate_diagnostic_summary "${diagnostic_dir}" "${test_name}"

    track_progress "DIAG" "Complete" "Diagnostics captured in ${diagnostic_dir}"
}

# --- Reporting Functions ---
# Generates comprehensive test reports like medical summaries
generate_test_report() {
    local -a test_results=("$@")
    local report_file="${TEST_OUTPUT_DIR}/test_report.txt"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    track_progress "REPORT" "Starting" "Generating test report"
    
    {
        echo "GCP Resource Management Test Report"
        echo "=================================="
        echo
        echo "Execution Time: ${timestamp}"
        echo "Test Suite Version: ${TEST_SUITE_VERSION}"
        echo
        
        echo "Test Results:"
        printf "%s\n" "${test_results[@]}"
        echo
        
        echo "System Information:"
        echo "- Operating System: ${OSTYPE}"
        echo "- Shell Version: ${BASH_VERSION}"
        echo "- Working Directory: $(pwd)"
        echo
        
        if [[ -d "${TEST_OUTPUT_DIR}/diagnostics" ]]; then
            echo "Failed Tests:"
            find "${TEST_OUTPUT_DIR}/diagnostics" -type d -name "*_*" | while read -r dir; do
                test_name=$(basename "${dir}" | cut -d_ -f1)
                echo "- ${test_name}: Diagnostics in ${dir}"
            done
        fi
        
    } > "${report_file}"
    
    track_progress "REPORT" "Complete" "Report generated: ${report_file}"
}

# --- Test Execution with Safe Timeout ---
run_test_suite() {
    track_progress "TESTS" "Starting" "Test suite execution"

    local -a test_results=()
    local failed_tests=0

    # Find and execute all test functions
    for test_function in $(declare -F | grep "test_" | cut -d" " -f3 | sort); do
        track_progress "TEST" "Running" "${test_function}"

        if run_with_timeout 300 "${test_function}"; then
            test_results+=("✓ ${test_function}")
            track_progress "TEST" "Passed" "${test_function}"
        else
            local status=$?
            test_results+=("✗ ${test_function}")
            ((failed_tests++))
            track_progress "TEST" "Failed" "${test_function} (status: ${status})"
            capture_test_diagnostics "${test_function}"  # Pass the test function name as an argument
        fi
    done

    # Generate test report
    generate_test_report "${test_results[@]}"

    track_progress "TESTS" "Complete" "${#test_results[@]} tests run, ${failed_tests} failed"
    return "${failed_tests}"
}


# --- Cleanup ---
cleanup_test_environment() {
    track_progress "CLEANUP" "Starting" "Environment cleanup"
    
    if [[ -n "${TEMP_DIR:-}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
        track_progress "CLEANUP" "Removed" "Temporary directory"
    fi
    
    track_progress "CLEANUP" "Complete" "Environment cleaned"
}

# --- Main Entry Point ---
main() {
    # Process command line arguments
    local run_all=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --run-all)
                run_all=true
                shift
                ;;
            *)
                track_progress "ERROR" "Invalid" "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Initialize test environment
    if ! initialize_test_environment; then
        track_progress "ERROR" "Failed" "Environment initialization failed"
        return 1
    fi
    
    # Run tests based on mode
    local exit_code=0
    if [[ "${run_all}" == true ]]; then
        run_test_suite
        exit_code=$?
    else
        track_progress "INFO" "Skipped" "No tests specified"
    fi
    
    # Cleanup
    cleanup_test_environment
    
    return "${exit_code}"
}

# Execute main function if script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi