#!/bin/bash
#
# GCP Resource Management Error Handler
# File: gcp-error-handler.sh
# Version: 1.0.0
# Author: Ralf B Lukner MD PhD
#
# This module handles errors in GCP resource management operations through
# resource management system. It provides detailed, actionable error information
# and recovery suggestions for operators.
#
# Each error includes:
# - Unique error identifier for documentation reference
# - Detailed context about what went wrong
# - Specific suggestions for resolution
# - Recovery procedures when applicable
# - Links to relevant documentation
#
# Change ID: CL-20250128-0004

# --- Error Code Definition ---

# Define error categories (1-99: System, 100-199: Resource, 200-299: API)
declare -rA ERROR_CATEGORIES=(
    ["SYSTEM"]="1"
    ["RESOURCE"]="100"
    ["API"]="200"
)

# Define specific error codes with detailed information
declare -rA ERROR_CODES=(
    # System Errors (1-99)
    ["INVALID_CONFIG"]="1"
    ["PERMISSION_DENIED"]="2"
    ["STATE_CORRUPTION"]="3"
    ["LOCK_TIMEOUT"]="4"
    
    # Resource Errors (100-199)
    ["RESOURCE_NOT_FOUND"]="100"
    ["RESOURCE_BUSY"]="101"
    ["INVALID_STATE"]="102"
    ["DEPENDENCY_VIOLATION"]="103"
    
    # API Errors (200-299)
    ["API_QUOTA_EXCEEDED"]="200"
    ["API_RATE_LIMITED"]="201"
    ["API_AUTHENTICATION"]="202"
    ["API_TIMEOUT"]="203"
)

# --- Error Templates ---

# Define detailed error message templates
declare -rA ERROR_TEMPLATES=(
    ["INVALID_CONFIG"]="Configuration error: %s
Resolution: Verify configuration file at %s matches required schema.
Documentation: See configuration_guide.md section 3.2"

    ["PERMISSION_DENIED"]="Permission denied: %s
Required permissions: %s
Resolution: Grant required permissions or use authorized credentials.
Documentation: See security_guide.md section 2.1"

    ["STATE_CORRUPTION"]="State file corruption detected: %s
Impact: System state may be inconsistent
Resolution: Run 'gcp-recovery.sh --verify-state' to check and repair state
Documentation: See troubleshooting_guide.md section 4.3"

    ["LOCK_TIMEOUT"]="Resource lock timeout: %s
Timeout after: %d seconds
Current lock holder: PID %d (%s)
Resolution: Check for hung processes or manually release lock
Documentation: See operations_guide.md section 5.2"

    ["RESOURCE_NOT_FOUND"]="Resource not found: %s
Project: %s
Type: %s
Resolution: Verify resource name and project ID
Documentation: See resource_guide.md section 2.4"

    ["API_QUOTA_EXCEEDED"]="API quota exceeded: %s
Current usage: %d/%d
Reset time: %s
Resolution: Wait for quota reset or request quota increase
Documentation: See quota_guide.md section 3.1"
)

# --- Error Handling Functions ---

handle_error() {
    local error_type="$1"
    local context="$2"
    shift 2
    local details=("$@")
    
    # Get base error code for category
    local category_code="${ERROR_CATEGORIES[${error_type%%_*}]}"
    if [[ -z "${category_code}" ]]; then
        category_code="${ERROR_CATEGORIES[SYSTEM]}"
    fi
    
    # Get specific error code
    local error_code="${ERROR_CODES[${error_type}]}"
    if [[ -z "${error_code}" ]]; then
        error_code="${category_code}"
    fi
    
    # Generate unique error identifier
    local error_id
    error_id="ERR-$(date +%Y%m%d-%H%M%S)-${error_code}"

    # Format error message from template
    local error_message
    if [[ -n "${ERROR_TEMPLATES[${error_type}]}" ]]; then
        # shellcheck disable=SC2059
        error_message=$(printf "${ERROR_TEMPLATES[${error_type}]}" "${details[@]}")
    else
        error_message="Unknown error: ${error_type} (${context})"
    fi
    
    # Log detailed error information
    log_error "${error_id}" "${error_type}" "${context}" "${error_message}"
    
    # Attempt recovery if available
    if ! attempt_recovery "${error_type}" "${context}" "${error_id}"; then
        log "WARN" "Recovery failed for error ${error_id}"
    fi
    
    # Return error code for proper error propagation
    return "${error_code}"
}

log_error() {
    local error_id="$1"
    local error_type="$2"
    local context="$3"
    local message="$4"
    
    # Log to system log
    log "ERROR" "Error ID: ${error_id}"
    log "ERROR" "Type: ${error_type}"
    log "ERROR" "Context: ${context}"
    log "ERROR" "Details:"
    while IFS= read -r line; do
        log "ERROR" "  ${line}"
    done <<< "${message}"
    
    # Generate detailed error report
    local report_file="${LOG_DIR}/error_${error_id}.log"
    {
        echo "Error Report: ${error_id}"
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Type: ${error_type}"
        echo "Context: ${context}"
        echo
        echo "Details:"
        echo "${message}"
        echo
        echo "System State:"
        get_system_state
        echo
        echo "Stack Trace:"
        print_stack_trace
    } > "${report_file}"
    
    # Set appropriate permissions
    chmod 0640 "${report_file}"
}

attempt_recovery() {
    local error_type="$1"
    local context="$2"
    local error_id="$3"
    
    log "INFO" "Attempting recovery for ${error_id}"
    
    # Implement recovery procedures based on error type
    case "${error_type}" in
        STATE_CORRUPTION)
            repair_state_corruption "${context}"
            ;;
        LOCK_TIMEOUT)
            release_stale_locks "${context}"
            ;;
        API_QUOTA_EXCEEDED)
            implement_backoff "${context}"
            ;;
        *)
            log "INFO" "No automated recovery available for ${error_type}"
            return 1
            ;;
    esac
}

print_stack_trace() {
    local frame=0
    local frames=()
    
    # Collect stack frames
    while caller "${frame}"; do
        frames+=("$BASH_COMMAND")
        ((frame++))
    done
    
    # Print stack trace in reverse order
    for ((i=${#frames[@]}-1; i>=0; i--)); do
        echo "  at ${frames[i]}"
    done
}

get_system_state() {
    {
        echo "Process Information:"
        ps -p "$$" -o pid,ppid,cmd
        
        echo -e "\nEnvironment Variables:"
        env | grep -E '^(GCP_|GOOGLE_|PROJECT_|REGION_|ZONE_)'
        
        echo -e "\nResource Locks:"
        ls -l "${LOCK_DIR}"
        
        echo -e "\nRecent Log Entries:"
        tail -n 20 "${LOG_FILE}"
    } 2>&1
}

# Example usage:
# handle_error "RESOURCE_NOT_FOUND" "delete_instance" "instance-123" "my-project" "compute"
# handle_error "API_QUOTA_EXCEEDED" "list_instances" "Compute Engine API" "1000" "1200" "2025-01-29T00:00:00Z"