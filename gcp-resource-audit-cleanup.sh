#!/bin/bash
#
# Enhanced GCP Resource Collection and Deletion Script with Temporal Information
# Version: 3.2.2
# Purpose: Collect, analyze, and safely delete GCP project resources with temporal context

# --- Shell Settings for Strict Mode ---
# Exit on error, treat unset vars as error, and fail on pipe errors.
# If you prefer continuing after some errors, remove/set +e as needed.
set -o errexit
set -o nounset
set -o pipefail

# --- Color constants for visual feedback ---
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r NO_COLOR='\033[0m'

# --- Configuration variables ---
declare -r MAX_PREVIEW_LINES=5
declare -r MAX_BUCKET_FILES=5
declare -r MAX_TABLE_ROWS=5
declare -r LOG_DIR="${HOME}/gcp-logs"
declare -r TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
# Default: consider resources idle after 30 days
DAYS_IDLE=30  

# --- Usage function ---
show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] <PROJECT_ID>

Collect and analyze GCP project resources with options to delete unused ones, including temporal information.

Options:
    -o, --output-dir DIR    Specify custom output directory (default: ../projects-data)
    -d, --days IDLE_DAYS    Consider resources idle for this many days (default: 30)
    -v, --verbose           Enable verbose logging
    -i, --interactive       Interactive mode for resource deletion
    -h, --help              Display this help message

Example:
    $(basename "$0") --output-dir /path/to/output --days 60 my-project-id
EOF
    exit 1
}

# --- Enhanced logging function ---
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    case "$level" in
        "INFO")  echo -e "${GREEN}[INFO]${NO_COLOR} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NO_COLOR} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NO_COLOR} $message" ;;
        "DEBUG") [[ "${VERBOSE:-false}" == true ]] && echo -e "${BLUE}[DEBUG]${NO_COLOR} $message" ;;
    esac

    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# --- Error handling (trap for ERR) ---
handle_error() {
    local exit_code="$?"
    local line_number="$1"
    log "ERROR" "Error occurred at line $line_number (Exit code: $exit_code)"
    log "ERROR" "Stack trace:"
    local frame=0
    while caller "$frame"; do
        ((frame++))
    done | awk '{print "  at line " $1 " in function " $2 " (file: " $3 ")"}'
    exit "$exit_code"
}
trap 'handle_error ${LINENO}' ERR

# --- Check dependencies ---
check_dependencies() {
    local deps=("gcloud" "jq" "awk")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log "ERROR" "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# --- Validate GCP authentication ---
validate_gcp_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        log "ERROR" "No active GCP authentication. Run 'gcloud auth login'"
        exit 1
    fi
}

# --- Safe execute function (array-based) with retry ---
safe_execute() {
    local -a cmd=("${!1}")  # Pass the name of an array, then expand it here
    local description="$2"
    local max_retries="${3:-3}"
    local retry_count=0
    local success=false

    while [ "$retry_count" -lt "$max_retries" ] && [ "$success" = false ]; do
        log "DEBUG" "Attempting: $description (Attempt $((retry_count + 1))/$max_retries)"
        if "${cmd[@]}" >> "$OUTPUT_FILE" 2>&1; then
            success=true
            log "INFO" "Executed successfully: $description"
        else
            ((retry_count++))
            if [ "$retry_count" -lt "$max_retries" ]; then
                log "WARN" "Failed attempt $retry_count/$max_retries. Retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    if [ "$success" = false ]; then
        log "ERROR" "Failed after $max_retries attempts: $description"
        echo "Error: $description. Check permissions or project status." >> "$OUTPUT_FILE"
    fi
}

# --- Collect Compute Engine resources ---
collect_compute_resources() {
    log "INFO" "Collecting Compute Engine resources..."

    # Instances
    local -a cmd_instances=(
        gcloud compute instances list
        --project="$PROJECT_ID"
        --format="table(
            name,
            zone,
            status,
            networkInterfaces[0].networkIP,
            networkInterfaces[0].accessConfigs[0].natIP,
            machineType.basename(),
            creationTimestamp.date(),
            lastStartedTimestamp.date(),
            lastStoppedTimestamp.date()
        )"
    )
    safe_execute cmd_instances[@] "Compute Engine Instances"

    # Disks
    local -a cmd_disks=(
        gcloud compute disks list
        --project="$PROJECT_ID"
        --format="table(name,zone,sizeGb,status,creationTimestamp.date())"
    )
    safe_execute cmd_disks[@] "Compute Engine Disks"

    # Snapshots
    local -a cmd_snapshots=(
        gcloud compute snapshots list
        --project="$PROJECT_ID"
        --format="table(name,sourceDisk,createTime)"
        --sort-by=~createTime
    )
    safe_execute cmd_snapshots[@] "Compute Engine Snapshots"
}

# --- Collect Storage resources ---
collect_storage_resources() {
    log "INFO" "Collecting Storage resources..."

    local buckets
    if ! buckets="$(gcloud storage buckets list --project="$PROJECT_ID" --format="value(name)")"; then
        log "ERROR" "Failed to list storage buckets"
        return 1
    fi

    if [ -z "$buckets" ]; then
        log "INFO" "No storage buckets found."
        return 0
    fi

    echo -e "\nCloud Storage Buckets:" >> "$OUTPUT_FILE"
    while IFS= read -r bucket; do
        echo -e "\nBucket: $bucket" >> "$OUTPUT_FILE"

        # Bucket metadata
        local -a cmd_bucket_meta=(
            gcloud storage buckets describe "$bucket"
            --format="json(location,storageClass,timeCreated,lifecycleRules)"
        )
        safe_execute cmd_bucket_meta[@] "Bucket metadata for $bucket"

        # Recent files
        local -a cmd_bucket_list=(
            gcloud storage objects list "$bucket"
            --limit="$MAX_BUCKET_FILES"
            --format="table(name,size,updated,lastAccessed)"
            --sort-by=~updated
        )
        safe_execute cmd_bucket_list[@] "Recent files in $bucket"
    done <<< "$buckets"
}

# --- Collect additional GCP resources ---
collect_additional_resources() {
    log "INFO" "Collecting additional resources..."

    # Cloud Functions
    local -a cmd_functions=(
        gcloud functions list
        --project="$PROJECT_ID"
        --format="table(name,region,status,latestDeployment.time,lastInvokedTime)"
        --sort-by=~latestDeployment.time
    )
    safe_execute cmd_functions[@] "Cloud Functions"

    # Pub/Sub Topics
    local -a cmd_pubsub=(
        gcloud pubsub topics list
        --project="$PROJECT_ID"
        --format="table(name,CreateTime,lastModifiedTime)"
        --sort-by=~CreateTime
    )
    safe_execute cmd_pubsub[@] "Pub/Sub Topics"

    # Cloud Build Triggers
    local -a cmd_build_triggers=(
        gcloud build triggers list
        --project="$PROJECT_ID"
        --format="table(name,repository,eventConfig.filter,status,createTime,lastRunTime)"
        --sort-by=~createTime
    )
    safe_execute cmd_build_triggers[@] "Cloud Build Triggers"
}

# --- Recommend resources for deletion ---
recommend_deletion() {
    log "INFO" "Analyzing resources for deletion candidates..."

    # Stopped Compute Instances
    local stopped_instances
    stopped_instances="$(gcloud compute instances list --project="$PROJECT_ID" \
        --filter="status=TERMINATED" \
        --format='value(name)' || true )"

    if [ -n "$stopped_instances" ]; then
        echo -e "\nStopped Compute Instances (candidates for deletion):" >> "$OUTPUT_FILE"
        echo "$stopped_instances" >> "$OUTPUT_FILE"
    fi

    # Old Compute Snapshots
    local old_snapshots
    old_snapshots="$(gcloud compute snapshots list --project="$PROJECT_ID" \
        --filter="createTime < $(date --date="$DAYS_IDLE days ago" +%Y-%m-%dT%H:%M:%SZ)" \
        --format='value(name)' \
        --sort-by=~createTime || true )"

    if [ -n "$old_snapshots" ]; then
        echo -e "\nOld Compute Snapshots (candidates for deletion):" >> "$OUTPUT_FILE"
        echo "$old_snapshots" >> "$OUTPUT_FILE"
    fi

    # Idle Storage Buckets (very rough filter based on creation time)
    local idle_buckets
    idle_buckets="$(gcloud storage buckets list --project="$PROJECT_ID" \
        --filter="timeCreated < $(date --date="$DAYS_IDLE days ago" +%s)000" \
        --format='value(name)' || true )"

    if [ -n "$idle_buckets" ]; then
        echo -e "\nStorage Buckets with no recent activity (candidates for deletion):" >> "$OUTPUT_FILE"
        echo "$idle_buckets" >> "$OUTPUT_FILE"
    fi

    # Unused Cloud Functions
    local unused_functions
    unused_functions="$(gcloud functions list --project="$PROJECT_ID" \
        --filter="lastInvokedTime < $(date --date="$DAYS_IDLE days ago" +%Y-%m-%dT%H:%M:%SZ)" \
        --format='value(name)' \
        --sort-by=~lastInvokedTime || true )"

    if [ -n "$unused_functions" ]; then
        echo -e "\nUnused Cloud Functions (candidates for deletion):" >> "$OUTPUT_FILE"
        echo "$unused_functions" >> "$OUTPUT_FILE"
    fi
}

# --- Interactive deletion mode ---
interactive_deletion() {
    if [ "${INTERACTIVE:-false}" != true ]; then
        return
    fi

    log "INFO" "Entering interactive deletion mode..."
    echo -e "\nPlease review the resources listed in $OUTPUT_FILE and select which ones to delete."
    echo "Enter the resource name or 'all' to delete all candidates. Enter 'exit' to finish."

    while true; do
        read -r -p "Enter resource to delete or 'exit': " input

        case "$input" in
            exit)
                break
                ;;
            all)
                # Delete all recommended resources
                log "INFO" "Deleting all recommended resources..."
                # Implement your delete logic here
                ;;
            "")
                # Just ignore empty input
                ;;
            *)
                # Delete specific resource
                log "INFO" "Attempting to delete: $input"
                # Implement your delete logic here
                ;;
        esac
    done
}

# --- Main Execution ---

# Defaults
VERBOSE=false
OUTPUT_BASE_DIR="../projects-data"
INTERACTIVE=false
PROJECT_ID=""

# --- Parse command-line arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output-dir)
            OUTPUT_BASE_DIR="$2"
            shift 2
            ;;
        -d|--days)
            # Validate numeric
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --days requires a numeric argument."
                exit 1
            fi
            DAYS_IDLE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=true
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "Unknown option: $1"
            show_usage
            ;;
        *)
            PROJECT_ID="$1"
            shift
            ;;
    esac
done

# Validate required argument
if [ -z "$PROJECT_ID" ]; then
    show_usage
fi

# Setup directories and logging
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/collection_${TIMESTAMP}.log"
OUTPUT_DIR="${OUTPUT_BASE_DIR}/${PROJECT_ID}_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="${OUTPUT_DIR}/project_resources.txt"

# Start logging
log "INFO" "Starting resource collection for project: $PROJECT_ID"
log "INFO" "Output directory: $OUTPUT_DIR"

# --- Perform initial checks ---
check_dependencies
validate_gcp_auth

# --- Verify project access ---
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    log "ERROR" "Unable to access project: $PROJECT_ID. Check permissions."
    exit 1
fi

# --- Collect resources ---
collect_compute_resources
collect_storage_resources
collect_additional_resources

# --- Recommend resources for deletion ---
recommend_deletion

# --- Interactive deletion if enabled ---
interactive_deletion

log "INFO" "Resource collection and analysis completed successfully."
log "INFO" "Results saved to: $OUTPUT_FILE"

if [ "$INTERACTIVE" == true ]; then
    log "INFO" "Interactive deletion mode exited."
fi

echo -e "\nScript completed. Review $OUTPUT_FILE for resource details and recommendations."
