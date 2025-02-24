#!/opt/homebrew/bin/bash
#
# GCP Resource Management Utilities
# Version: 3.2.7
# Author: Ralf B Lukner MD PhD
# Overview: This script provides core utility functions for managing Google Cloud Platform (GCP) resources.
# Now updated with proper variable initialization and error checking.

# Enable bash strict mode for better error detection
set -o nounset  # Error on undefined variables
set -o errexit  # Exit on error
set -o pipefail # Exit on pipe failure

# --- Early Variables for Error Handling ---
# These must be defined before any other operations
if [[ -z "${TMPDIR:-}" ]]; then
    TMPDIR="/tmp"
fi

if [[ -z "${HOME:-}" ]]; then
    echo "ERROR: HOME environment variable is not set" >&2
    exit 1
fi

# --- Global Constants and Configuration ---

# Script information
SCRIPT_VERSION="3.2.7"
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# System directories - created with proper permissions
readonly CONFIG_DIR="${HOME}/.gcp-resource-mgmt"
readonly LOG_DIR="${CONFIG_DIR}/logs"
TEMP_DIR="${CONFIG_DIR}/temp"
readonly LOCK_DIR="${CONFIG_DIR}/locks"
readonly STATE_DIR="${CONFIG_DIR}/state"

# Logging levels with proper ordering for filtering
declare -A LOG_LEVELS
LOG_LEVELS=(
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
    local timestamp
    timestamp=$(date -u +"%Y%m%d_%H%M%S")
    CURRENT_LOG_FILE="${LOG_DIR}/gcp_utils_${timestamp}.log"
    export CURRENT_LOG_FILE
    
    # Create log file with proper permissions
    touch "${CURRENT_LOG_FILE}" || {
        echo "ERROR: Failed to create log file: ${CURRENT_LOG_FILE}" >&2
        return ${E_GENERAL}
    }
    chmod 0640 "${CURRENT_LOG_FILE}"
    
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
    local message="${1:-Unknown error}"
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
    local error_code="${1:-${E_GENERAL}}"
    local context="${2:-}"
    
    log "INFO" "Attempting error recovery (code: ${error_code})"
    
    # Release any held locks
    release_all_locks
    
    # Clean up temporary resources
    cleanup_temp_resources
    
    # Restore previous state if available
    restore_previous_state
    
    return ${E_SUCCESS}
}

# --- Logging and Output ---

log() {
    local level="${1:-INFO}"
    shift
    local message="${*:-No message provided}"
    
    # Validate log level
    if [[ -z "${LOG_LEVELS[$level]:-}" ]]; then
        level="ERROR"
        message="Invalid log level specified for message: $*"
    fi
    
    # Format timestamp
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file if it exists
    if [[ -n "${CURRENT_LOG_FILE:-}" ]] && [[ -w "${CURRENT_LOG_FILE}" ]]; then
        printf "[%s] [%s] %s\n" "${timestamp}" "${level}" "${message}" \
            >> "${CURRENT_LOG_FILE}"
    fi
    
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
            [[ -n "${DEBUG:-}" ]] && \
                printf "${BLUE}[%s] %s${NC}\n" "${level}" "${message}"
            ;;
    esac
}

# --- State Management ---

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

# --- Resource State Management ---

update_resource_state() {
    local resource_id="${1:-}"
    local state="${2:-}"
    local state_file="${STATE_DIR}/current_state.json"
    
    # Validate inputs
    if [[ -z "${resource_id}" ]] || [[ -z "${state}" ]]; then
        handle_error "Invalid resource state update parameters" ${E_INVALID_INPUT}
        return ${E_INVALID_INPUT}
    fi

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

# --- Cleanup ---

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