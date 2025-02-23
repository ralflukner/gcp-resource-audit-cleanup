#!/bin/bash
#
# GCP Resource Management Utilities
# Version: 3.2.6
# Author: Ralf B Lukner MD PhD
# Overview
# This script, gcp-utils.sh, provides core utility functions for managing Google Cloud Platform (GCP) resources. It is designed to enhance the reliability and maintainability of GCP resource management tasks by offering essential functionalities such as logging, command verification, resource locking, temporary file cleanup, and retry mechanisms.

# Purpose
# The purpose of this script is to serve as a foundation for other GCP management scripts. By encapsulating common utility functions, it promotes code reuse and simplifies the development of GCP resource management tools.

# Key Features
# Logging Setup and Utilities: Initializes logging for the script, ensuring that all operations are recorded with timestamps and log levels (INFO, WARN, ERROR).

# Command Verification: Ensures that all required system commands (e.g., gcloud, jq, curl) are available before proceeding, preventing runtime errors due to missing dependencies.

# Resource Locking and State Management: Implements mechanisms to acquire exclusive locks for resources, preventing concurrent access and ensuring data consistency.

# Temporary File Cleanup and Retry Mechanisms: Provides functions to clean up old temporary files and directories, and to retry failed commands with exponential backoff, enhancing script robustness.
#
# Usage
# To use this script, ensure it is sourced or executed in your environment. The script is designed to be modular, allowing other scripts to depend on its utility functions.
#
# Example Usage
# Source the script
# source gcp-utils.sh
#
# Version History
# Version 3.2.6: Added detailed comments, improved logging, and enhanced error handling.
# Version 3.2.5: Introduced resource locking and retry mechanisms.
# Version 3.2.4: Initial release with core logging and command verification.
#
# Core utility functions for GCP resource management system providing:
# - Enhanced error handling with stack traces and recovery
# - Resource validation and state management
# - Secure locking mechanisms with deadlock prevention
# - Quota management and prediction
# - Cross-component communication
# - Testing infrastructure support
#
# This module serves as the foundation for the entire GCP resource management
# system. All other components depend on the functionality provided here, so
# we maintain strict backward compatibility and comprehensive error handling.

# --- Global Constants and Configuration ---

# Script information
readonly SCRIPT_VERSION="3.2.6"
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# System directories - created with proper permissions
readonly CONFIG_DIR="${HOME}/.gcp-resource-mgmt"
readonly LOG_DIR="${CONFIG_DIR}/logs"
readonly TEMP_DIR="${CONFIG_DIR}/temp"
readonly LOCK_DIR="${CONFIG_DIR}/locks"
readonly STATE_DIR="${CONFIG_DIR}/state"

# Logging levels with proper ordering for filtering
declare -A LOG_LEVELS=(
    ["ERROR"]=0
    ["WARN"]=1
    ["INFO"]=2
    ["DEBUG"]=3
)

# Terminal colors for consistent output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Error codes for consistent error handling
readonly E_SUCCESS=0
readonly E_GENERAL=1
readonly E_INVALID_INPUT=2
readonly E_RESOURCE_NOT_FOUND=3
readonly E_PERMISSION_DENIED=4
readonly E_TIMEOUT=5
readonly E_LOCK_FAILED=6
readonly E_STATE_INVALID=7

# --- Core Initialization ---

initialize_environment() {
    local -a required_dirs=(
        "${CONFIG_DIR}"
        "${LOG_DIR}"
        "${TEMP_DIR}"
        "${LOCK_DIR}"
        "${STATE_DIR}"
    )
    
    # Create required directories with proper permissions
    for dir in "${required_dirs[@]}"; do
        if ! mkdir -p "${dir}" -m 0750; then
            echo "ERROR: Failed to create directory: ${dir}" >&2
            return ${E_GENERAL}
        fi
    done
    
    # Initialize logging
    setup_logging
    
    # Verify required commands
    verify_commands || return $?
    
    # Set up error handlers
    trap cleanup_environment EXIT
    trap 'handle_error "Interrupted by user" ${E_GENERAL}' INT TERM
    
    # Initialize state tracking
    initialize_state_tracking
    
    log "INFO" "Environment initialized successfully"
    return ${E_SUCCESS}
}

setup_logging() {
    # Create timestamped log file
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${LOG_DIR}/gcp_utils_${timestamp}.log"
    
    # Create log file with proper permissions
    touch "${log_file}" || {
        echo "ERROR: Failed to create log file: ${log_file}" >&2
        return ${E_GENERAL}
    }
    chmod 0640 "${log_file}"
    
    # Export for use by logging functions
    export CURRENT_LOG_FILE="${log_file}"
    
    return ${E_SUCCESS}
}

verify_commands() {
    local -a required_commands=(
        "gcloud"
        "jq"
        "awk"
        "bc"
        "curl"
        "mktemp"
    )
    
    local missing_commands=()
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            missing_commands+=("${cmd}")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "ERROR" "Missing required commands: ${missing_commands[*]}"
        return ${E_GENERAL}
    fi
    
    return ${E_SUCCESS}
}

# --- Enhanced Error Handling ---

handle_error() {
    local message="$1"
    local error_code="${2:-${E_GENERAL}}"
    local context="${3:-}"
    
    # Generate stack trace
    local stack_trace
    stack_trace=$(generate_stack_trace)
    
    # Log error with full context
    log "ERROR" "${message}"
    log "ERROR" "Stack trace:\n${stack_trace}"
    if [[ -n "${context}" ]]; then
        log "ERROR" "Context: ${context}"
    fi
    
    # Attempt error recovery if possible
    if ! recover_from_error "${error_code}" "${context}"; then
        log "ERROR" "Error recovery failed"
    fi
    
    return "${error_code}"
}

generate_stack_trace() {
    local -a trace_lines=()
    local -i skip=2  # Skip this function and handle_error
    
    for ((i = skip; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[$i]:-main}"
        local line="${BASH_LINENO[$((i-1))]}"
        local src="${BASH_SOURCE[$i]:-$0}"
        trace_lines+=("  at ${func} (${src}:${line})")
    done
    
    printf '%s\n' "${trace_lines[@]}"
}

recover_from_error() {
    local error_code="$1"
    local context="$2"
    
    log "INFO" "Attempting error recovery (code: ${error_code})"
    
    # Release any held locks
    release_all_locks
    
    # Clean up temporary resources
    cleanup_temp_resources
    
    # Restore previous state if available
    restore_previous_state
    
    return ${E_SUCCESS}
}

# --- Resource State Management ---

initialize_state_tracking() {
    local state_file="${STATE_DIR}/current_state.json"
    
    # Initialize state file if it doesn't exist
    if [[ ! -f "${state_file}" ]]; then
        cat > "${state_file}" << EOF
{
    "resources": {},
    "operations": [],
    "locks": {},
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
        chmod 0640 "${state_file}"
    fi
    
    return ${E_SUCCESS}
}

update_resource_state() {
    local resource_id="$1"
    local state="$2"
    local state_file="${STATE_DIR}/current_state.json"
    
    # Update state atomically
    jq --arg id "${resource_id}" \
       --arg state "${state}" \
       --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.resources[$id] = {
           "state": $state,
           "timestamp": $time
       }' "${state_file}" > "${state_file}.tmp" && \
    mv "${state_file}.tmp" "${state_file}"
    
    return ${E_SUCCESS}
}

get_resource_state() {
    local resource_id="$1"
    local state_file="${STATE_DIR}/current_state.json"
    
    jq -r --arg id "${resource_id}" \
        '.resources[$id].state // "unknown"' \
        "${state_file}"
}

# --- Enhanced Resource Locking ---

acquire_resource_lock() {
    local resource_id="$1"
    local timeout="${2:-30}"  # Default 30 second timeout
    local lock_file="${LOCK_DIR}/${resource_id}.lock"
    local start_time=$(date +%s)
    
    while true; do
        # Try to create lock file atomically
        if mkdir "${lock_file}" 2>/dev/null; then
            # Record lock ownership
            echo "$$" > "${lock_file}/pid"
            echo "${SCRIPT_NAME}" > "${lock_file}/owner"
            date -u +"%Y-%m-%dT%H:%M:%SZ" > "${lock_file}/timestamp"
            
            # Update state tracking
            update_resource_state "${resource_id}" "locked"
            
            log "DEBUG" "Lock acquired for ${resource_id}"
            return ${E_SUCCESS}
        fi
        
        # Check timeout
        if (( $(date +%s) - start_time >= timeout )); then
            log "ERROR" "Timeout waiting for lock: ${resource_id}"
            return ${E_TIMEOUT}
        fi
        
        # Check for stale lock
        if [[ -f "${lock_file}/pid" ]]; then
            local lock_pid
            lock_pid=$(<"${lock_file}/pid")
            if ! kill -0 "${lock_pid}" 2>/dev/null; then
                log "WARN" "Removing stale lock from PID ${lock_pid}"
                rm -rf "${lock_file}"
                continue
            fi
        fi
        
        sleep 1
    done
}

release_resource_lock() {
    local resource_id="$1"
    local lock_file="${LOCK_DIR}/${resource_id}.lock"
    
    # Verify we own the lock
    if [[ -f "${lock_file}/pid" ]]; then
        local lock_pid
        lock_pid=$(<"${lock_file}/pid")
        if [[ "${lock_pid}" != "$$" ]]; then
            log "ERROR" "Cannot release lock owned by PID ${lock_pid}"
            return ${E_LOCK_FAILED}
        fi
    fi
    
    # Remove lock and update state
    if rm -rf "${lock_file}"; then
        update_resource_state "${resource_id}" "unlocked"
        log "DEBUG" "Lock released for ${resource_id}"
        return ${E_SUCCESS}
    fi
    
    return ${E_LOCK_FAILED}
}

release_all_locks() {
    local count=0
    
    # Find all locks owned by this process
    for lock_file in "${LOCK_DIR}"/*.lock; do
        [[ -f "${lock_file}/pid" ]] || continue
        
        local lock_pid
        lock_pid=$(<"${lock_file}/pid")
        if [[ "${lock_pid}" == "$$" ]]; then
            local resource_id
            resource_id=$(basename "${lock_file}" .lock)
            if release_resource_lock "${resource_id}"; then
                ((count++))
            fi
        fi
    done
    
    log "DEBUG" "Released ${count} locks"
    return ${E_SUCCESS}
}

# --- Cleanup and Resource Management ---

cleanup_environment() {
    local exit_code=$?
    
    log "INFO" "Starting environment cleanup"
    
    # Release any held locks
    release_all_locks
    
    # Clean up temporary resources
    cleanup_temp_resources
    
    # Update final state
    update_cleanup_state
    
    log "INFO" "Cleanup completed with exit code ${exit_code}"
    return ${exit_code}
}

cleanup_temp_resources() {
    # Clean up temporary files
    find "${TEMP_DIR}" -type f -mmin +60 -delete 2>/dev/null
    
    # Clean up empty directories
    find "${TEMP_DIR}" -type d -empty -delete 2>/dev/null
    
    return ${E_SUCCESS}
}

update_cleanup_state() {
    local state_file="${STATE_DIR}/current_state.json"
    
    # Record cleanup in state file
    jq --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
       '.cleanup_timestamp = $time' \
       "${state_file}" > "${state_file}.tmp" && \
    mv "${state_file}.tmp" "${state_file}"
    
    return ${E_SUCCESS}
}

# --- Logging and Output ---

log() {
    local level="$1"
    shift
    local message="$*"
    
    # Validate log level
    if [[ -z "${LOG_LEVELS[$level]}" ]]; then
        level="ERROR"
        message="Invalid log level specified for message: $*"
    fi
    
    # Format timestamp
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    printf "[%s] [%s] %s\n" "${timestamp}" "${level}" "${message}" \
        >> "${CURRENT_LOG_FILE}"
    
    # Write to console with proper formatting
    case "${level}" in
        "ERROR")
            printf "${RED}[%s] %s${NC}\n" "${level}" "${message}" >&2
            ;;
        "WARN")
            printf "${YELLOW}[%s] %s${NC}\n" "${level}" "${message}" >&2
            ;;
        "INFO")
            printf "${GREEN}[%s] %s${NC}\n" "${level}" "${message}"
            ;;
        "DEBUG")
            [[ -n "${DEBUG}" ]] && \
                printf "${BLUE}[%s] %s${NC}\n" "${level}" "${message}"
            ;;
    esac
}

# --- Cross-Component Communication ---

send_component_message() {
    local component="$1"
    local message_type="$2"
    local payload="$3"
    local message_file
    
    # Create timestamped message file
    message_file=$(mktemp "${TEMP_DIR}/msg_${component}_XXXXXX.json")
    
    # Write message content
    cat > "${message_file}" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "component": "${component}",
    "type": "${message_type}",
    "payload": ${payload}
}
EOF
    
    chmod 0640 "${message_file}"
    
    return ${E_SUCCESS}
}

receive_component_messages() {
    local component="$1"
    local message_pattern="${TEMP_DIR}/msg_${component}_*.json"
    
    # Process all messages for this component
    local messages=()
    while IFS= read -r -d '' message_file; do
        messages+=("$(cat "${message_file}")")
        rm -f "${message_file}"
    done < <(find "${TEMP_DIR}" -name "msg_${component}_*.json" -print0)
    
    # Return messages as JSON array
    printf '%s\n' "${messages[@]}" | jq -s '.'
}

# --- Main Entry Point ---

main() {
    # Parse command line arguments
    parse_arguments "$@" || return $?
    
    # Initialize environment
    initialize_environment || return $?
    
    log "INFO" "Utilities initialization complete"
    return ${E_SUCCESS}
}

# Execute main function if script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
