#!/bin/bash
#
# GCP Resource Management Utilities
# Version: 1.1.0
# Previous Version: 1.0.1
# Author: Ralf B Lukner MD PhD
#
# Core utility functions for GCP resource management system providing:
# - Enhanced error handling with exponential backoff
# - Resource name validation against GCP naming conventions
# - Resource quota management and monitoring
# - Secure resource locking mechanisms
# - IAM permission validation
# - Dependency graph management
#
# Change Log:
# 2025-01-27 (1.1.0)
# - Added comprehensive error tracking with stack traces
# - Enhanced backoff algorithm with configurable jitter
# - Improved resource lock mechanism with atomic operations
# - Added quota prediction and trending analysis
# - Enhanced dependency graph with cycle detection

# --- Global Constants ---
readonly SCRIPT_VERSION="1.1.0"
readonly SCRIPT_NAME=$(basename "$0")
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}

# --- Environment Management ---

# Initializes the execution environment
initialize_environment() {
    # Create required directories
    mkdir -p "${TEMP_DIR:-/tmp/gcp-utils}"
    mkdir -p "${LOG_DIR:-/var/log/gcp-utils}"
    
    # Verify required commands
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
        log_error "Missing required commands: ${missing_commands[*]}"
        return 1
    fi
    
    # Verify gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" >/dev/null 2>&1; then
        log_error "No active gcloud account found. Please run 'gcloud auth login'"
        return 1
    fi
    
    # Set up signal handlers
    trap cleanup_environment EXIT
    trap 'log_error "Interrupted by user"; cleanup_environment; exit 1' INT TERM
    
    return 0
}

# Cleans up temporary resources
cleanup_environment() {
    local exit_code=$?
    
    # Release any held locks
    if [[ -d "${TEMP_DIR}/locks" ]]; then
        local lock_files=("${TEMP_DIR}"/locks/*.lock)
        for lock in "${lock_files[@]}"; do
            [[ -e "${lock}" ]] || continue
            local lock_pid
            if [[ -f "${lock}/pid" ]]; then
                lock_pid=$(<"${lock}/pid")
                if [[ "${lock_pid}" == "$" ]]; then
                    rm -rf "${lock}"
                fi
            fi
        done
    fi
    
    # Clean up temporary files
    if [[ -d "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
    
    # Final log message
    if [[ ${exit_code} -eq 0 ]]; then
        log "INFO" "Cleanup completed successfully"
    else
        log "WARN" "Cleanup completed with exit code ${exit_code}"
    fi
    
    return ${exit_code}
}

# --- Command Line Parsing ---

# Parses command line arguments
parse_arguments() {
    local -A options=(
        ["project-id"]=""
        ["verbose"]="false"
        ["output-dir"]=""
        ["days-idle"]=30
        ["interactive"]="false"
        ["help"]="false"
    )
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-id)
                options["project-id"]="$2"
                shift 2
                ;;
            --verbose)
                options["verbose"]="true"
                shift
                ;;
            --output-dir)
                options["output-dir"]="$2"
                shift 2
                ;;
            --days-idle)
                if [[ "$2" =~ ^[0-9]+$ ]]; then
                    options["days-idle"]="$2"
                else
                    log_error "Invalid value for --days-idle: $2"
                    return 1
                fi
                shift 2
                ;;
            --interactive)
                options["interactive"]="true"
                shift
                ;;
            --help)
                options["help"]="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required options
    if [[ ${options["help"]} == "false" && -z ${options["project-id"]} ]]; then
        log_error "Missing required option: --project-id"
        return 1
    fi
    
    # Export options as global variables
    for key in "${!options[@]}"; do
        declare -g "OPT_${key//-/_}=${options[${key}]}"
    done
    
    return 0
}

# Displays usage information
display_usage() {
    cat << EOF
GCP Resource Management Utilities
Version: ${SCRIPT_VERSION}

Usage: ${SCRIPT_NAME} --project-id PROJECT_ID [OPTIONS]

Required Options:
  --project-id      GCP Project ID

Optional Options:
  --verbose         Enable detailed logging
  --output-dir      Directory for output files
  --days-idle      Days threshold for resource idleness (default: 30)
  --interactive    Enable interactive mode
  --help           Display this help message

Examples:
  ${SCRIPT_NAME} --project-id my-project --verbose
  ${SCRIPT_NAME} --project-id my-project --days-idle 45 --interactive

For more information, please refer to the documentation.
EOF
}

# --- Main Function ---

# Main program entry point
main() {
    # Parse command line arguments
    if ! parse_arguments "$@"; then
        display_usage
        exit 1
    fi
    
    # Show help if requested
    if [[ "${OPT_help}" == "true" ]]; then
        display_usage
        exit 0
    fi
    
    # Initialize environment
    if ! initialize_environment; then
        log_error "Failed to initialize environment"
        exit 1
    fi
    
    # Enable verbose logging if requested
    if [[ "${OPT_verbose}" == "true" ]]; then
        DEBUG=true
    fi
    
    log "INFO" "Starting ${SCRIPT_NAME} version ${SCRIPT_VERSION}"
    log "INFO" "Project ID: ${OPT_project_id}"
    
    return 0
}

# Execute main function if script is not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi")" && pwd)"

# Color definitions for consistent output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Enhanced Error Handling ---

# Implements exponential backoff for API calls with jitter
implement_backoff() {
    local attempt="$1"
    local max_attempts="$2"
    local base_wait="${3:-1}"  # Allow configurable base wait time
    local max_jitter="${4:-1}" # Allow configurable jitter
    
    if [[ $attempt -ge $max_attempts ]]; then
        return 1
    fi
    
    # Enhanced exponential backoff with configurable parameters
    local max_wait=$(( base_wait * 2 ** attempt ))
    
    # Improved jitter calculation with better randomization
    local jitter=$(awk -v max="$max_jitter" \
                      'BEGIN {srand(); print rand() * max}')
    
    local wait_time=$(echo "scale=3; ${max_wait} + ${jitter}" | bc)
    
    # Add detailed logging for debugging
    log "DEBUG" "Backoff: attempt=${attempt}, wait=${wait_time}s, max=${max_wait}s"
    
    sleep "${wait_time}"
    return 0
}

# Enhanced error logging with stack trace
log_error() {
    local message="$1"
    local -i stack_start=${2:-1}  # Allow adjusting stack trace start point
    
    echo -e "${RED}[ERROR] ${message}${NC}" >&2
    
    # Generate stack trace
    local -i frame_count=0
    local stack_trace=""
    
    # Skip first N frames as specified by stack_start
    for ((i = stack_start; i < ${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[$i]:-main}"
        local line="${BASH_LINENO[$((i-1))]}"
        local src="${BASH_SOURCE[$i]:-$0}"
        stack_trace+="  at ${func} (${src}:${line})\n"
        ((frame_count++))
    done
    
    if [[ $frame_count -gt 0 ]]; then
        echo -e "Stack trace:\n${stack_trace}" >&2
    fi
}

# --- Resource Validation ---

# Validates resource names against GCP naming conventions
validate_resource_name() {
    local resource_name="$1"
    local resource_type="$2"
    
    # Enhanced regex patterns with stricter validation
    local -A patterns=(
        ["instance"]="^[a-z][-a-z0-9]{0,61}[a-z0-9]$"
        ["disk"]="^[a-z][-a-z0-9]{0,61}[a-z0-9]$"
        ["snapshot"]="^[a-z][-a-z0-9]{0,61}[a-z0-9]$"
        ["bucket"]="^[a-z0-9][a-z0-9-_.]{1,61}[a-z0-9]$"
        ["network"]="^[a-z][-a-z0-9]{0,61}[a-z0-9]$"
    )
    
    # Resource-specific validation rules
    local -A max_lengths=(
        ["instance"]=63
        ["disk"]=63
        ["snapshot"]=63
        ["bucket"]=63
        ["network"]=63
    )
    
    # Validate resource type
    if [[ ! ${patterns[$resource_type]} ]]; then
        log_error "Unknown resource type: ${resource_type}"
        return 1
    fi
    
    # Length validation
    local name_length=${#resource_name}
    if [[ ${name_length} -gt ${max_lengths[$resource_type]:-63} ]]; then
        log_error "Name exceeds maximum length for ${resource_type}"
        return 1
    fi
    
    # Pattern validation
    if [[ ! $resource_name =~ ${patterns[$resource_type]} ]]; then
        log_error "Invalid ${resource_type} name: ${resource_name}"
        return 1
    fi
    
    return 0
}

# --- Quota Management ---

# Enhanced quota checking with trend analysis
check_resource_quotas() {
    local resource_type="$1"
    local region="$2"
    local threshold="${3:-0.8}"  # Default warning at 80% usage
    
    log "INFO" "Checking quotas for ${resource_type} in ${region}"
    
    # Get historical quota usage for trend analysis
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time=$(date -u -d "7 days ago" +"%Y-%m-%dT%H:%M:%SZ")
    
    local quota_metrics
    quota_metrics=$(gcloud monitoring time-series list \
        "metric.type = compute.googleapis.com/quota/${resource_type}" \
        --filter="resource.labels.region = ${region}" \
        --interval="start=${start_time},end=${end_time}" \
        --format="json")
    
    if [[ -z "${quota_metrics}" ]]; then
        log_error "Failed to retrieve quota metrics for ${resource_type}"
        return 1
    fi
    
    # Analyze trends and predict quota exhaustion
    analyze_quota_trends "${quota_metrics}" "${threshold}"
    
    return $?
}

# Analyzes quota usage trends and predicts potential exhaustion
analyze_quota_trends() {
    local metrics="$1"
    local threshold="$2"
    
    # Extract usage values and timestamps
    local values timestamps
    readarray -t values < <(echo "${metrics}" | jq -r '.[].points[].value.doubleValue')
    readarray -t timestamps < <(echo "${metrics}" | jq -r '.[].points[].interval.endTime')
    
    # Calculate trend using simple linear regression
    local n=${#values[@]}
    local sum_x=0 sum_y=0 sum_xy=0 sum_xx=0
    local x y
    
    for ((i=0; i<n; i++)); do
        x=$i
        y=${values[$i]}
        sum_x=$((sum_x + x))
        sum_y=$(echo "${sum_y} + ${y}" | bc)
        sum_xy=$(echo "${sum_xy} + (${x} * ${y})" | bc)
        sum_xx=$((sum_xx + (x * x)))
    done
    
    # Calculate slope and intercept
    local slope intercept
    slope=$(echo "scale=4; (${n} * ${sum_xy} - ${sum_x} * ${sum_y}) / (${n} * ${sum_xx} - ${sum_x} * ${sum_x})" | bc)
    intercept=$(echo "scale=4; (${sum_y} - ${slope} * ${sum_x}) / ${n}" | bc)
    
    # Predict quota exhaustion
    if [[ $(echo "${slope} > 0" | bc) -eq 1 ]]; then
        local limit=$(echo "${metrics}" | jq -r '.[0].limit')
        local days_to_limit=$(echo "scale=0; (${limit} - ${intercept}) / ${slope}" | bc)
        
        if [[ ${days_to_limit} -lt 30 ]]; then
            log "WARN" "Quota ${resource_type} trending toward limit in ${days_to_limit} days"
            return 1
        fi
    fi
    
    return 0
}

# --- Resource Locking ---

# Enhanced resource locking with atomic operations
acquire_resource_lock() {
    local resource_id="$1"
    local lock_dir="${TEMP_DIR}/locks/${resource_id}.lock"
    local max_wait=60  # Maximum wait time in seconds
    local start_time=$(date +%s)
    
    mkdir -p "${TEMP_DIR}/locks"
    
    while ! mkdir "${lock_file}" 2>/dev/null; do
        local current_time=$(date +%s)
        if (( current_time - start_time >= max_wait )); then
            log_error "Timeout waiting for lock on resource: ${resource_id}"
            return 1
        fi
        
        # Check for stale locks
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
    
    # Record lock ownership
    echo "$$" > "${lock_file}/pid"
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "${lock_file}/timestamp"
    
    log "DEBUG" "Acquired lock for resource: ${resource_id}"
    return 0
}

# Safe resource lock release with ownership verification
release_resource_lock() {
    local resource_id="$1"
    local lock_file="${TEMP_DIR}/locks/${resource_id}.lock"
    
    if [[ -d "${lock_file}" ]]; then
        if [[ -f "${lock_file}/pid" ]]; then
            local lock_pid
            lock_pid=$(<"${lock_file}/pid")
            if [[ "${lock_pid}" != "$$" ]]; then
                log_error "Attempting to release lock owned by another process"
                return 1
            fi
        fi
        
        rm -rf "${lock_file}"
        log "DEBUG" "Released lock for resource: ${resource_id}"
        return 0
    fi
    
    return 0
}

# --- Dependency Management ---

# Enhanced dependency graph builder with cycle detection
build_dependency_graph() {
    local resource_type="$1"
    local resource_name="$2"
    local graph_file="${TEMP_DIR}/dependency_graph.json"
    
    log "INFO" "Building dependency graph for ${resource_type}:${resource_name}"
    
    # Initialize graph structure
    echo '{"nodes":[], "edges":[], "visited":{}}' > "${graph_file}"
    
    # Build graph recursively
    if ! build_graph_node "${resource_type}" "${resource_name}" "${graph_file}"; then
        log_error "Failed to build dependency graph"
        return 1
    fi
    
    # Detect cycles
    if detect_graph_cycles "${graph_file}"; then
        log_error "Dependency cycle detected in resource graph"
        return 1
    fi
    
    return 0
}

# Recursive graph building with cycle prevention
build_graph_node() {
    local resource_type="$1"
    local resource_name="$2"
    local graph_file="$3"
    
    # Check if node was already visited
    if jq -e --arg name "${resource_name}" \
        '.visited[$name] == true' "${graph_file}" >/dev/null; then
        return 0
    fi
    
    # Mark node as visited
    jq --arg name "${resource_name}" \
        '.visited[$name] = true' "${graph_file}" > "${graph_file}.tmp" && \
    mv "${graph_file}.tmp" "${graph_file}"
    
    # Add node to graph
    jq --arg name "${resource_name}" \
       --arg type "${resource_type}" \
       '.nodes += [{"id": $name, "type": $type}]' \
       "${graph_file}" > "${graph_file}.tmp" && \
    mv "${graph_file}.tmp" "${graph_file}"
    
    # Get dependencies based on resource type
    local dependencies
    case "${resource_type}" in
        "instances")
            dependencies=$(get_instance_dependencies "${resource_name}")
            ;;
        "disks")
            dependencies=$(get_disk_dependencies "${resource_name}")
            ;;
        # Add more resource types as needed
    esac
    
    # Process dependencies
    while read -r dep_type dep_name; do
        [[ -z "${dep_name}" ]] && continue
        
        # Add edge to graph
        jq --arg from "${resource_name}" \
           --arg to "${dep_name}" \
           --arg type "${dep_type}" \
           '.edges += [{"from": $from, "to": $to, "type": $type}]' \
           "${graph_file}" > "${graph_file}.tmp" && \
        mv "${graph_file}.tmp" "${graph_file}"
        
        # Recursively process dependency
        build_graph_node "${dep_type}" "${dep_name}" "${graph_file}"
    done <<< "${dependencies}"
    
    return 0
}

# Cycle detection in dependency graph
detect_graph_cycles() {
    local graph_file="$1"
    
    # Initialize visited and recursion stack arrays
    local -A visited=()
    local -A rec_stack=()
    
    # Get all nodes
    local nodes
    readarray -t nodes < <(jq -r '.nodes[].id' "${graph_file}")
    
    # Check each node for cycles
    for node in "${nodes[@]}"; do
        if [[ -z "${visited[${node}]}" ]]; then
            if is_cyclic_util "${node}" "${graph_file}" visited rec_stack; then
                return 1  # Cycle detected
            fi
        fi
    done
    
    return 0
}

# Utility function for cycle detection
is_cyclic_util() {
    local node="$1"
    local graph_file="$2"
    local -n visited="$3"
    local -n rec_stack="$4"
    
    visited[${node}]=1
    rec_stack[${node}]=1
    
    # Get adjacent nodes
    local adjacent
    readarray -t adjacent < <(jq -r --arg node "${node}" \
        '.edges[] | select(.from == $node) | .to' "${graph_file}")
    
    for adj in "${adjacent[@]}"; do
        if [[ -z "${visited[${adj}]}" ]]; then
            if is_cyclic_util "${adj}" "${graph_file}" visited rec_stack; then
                return 1
            fi
        elif [[ "${rec