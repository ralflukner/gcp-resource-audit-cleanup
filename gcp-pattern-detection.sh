#!/opt/homebrew/bin/bash
#
# GCP Resource Pattern Detection System
# File: gcp-pattern-detection.sh
# Version: 1.0.0
# Author: Ralf B Lukner MD PhD
#
# This module implements sophisticated pattern detection for GCP resource utilization.
# It analyzes various metrics to identify usage patterns and generate optimization
# recommendations. The system uses statistical analysis and trend detection to
# provide insights into resource usage efficiency.
#
# The pattern detection system works through several layers of analysis:
# 1. Raw metric collection and normalization
# 2. Statistical pattern analysis
# 3. Trend identification
# 4. Recommendation generation
#
# Dependencies:
#   - gcp-utils.sh v3.2.6 or later
#   - jq for JSON processing
#   - bc for floating point calculations
#   - awk for data processing
#
# Change ID: CL-20250128-0003

# Import core utilities
source "${SCRIPT_DIR}/gcp-utils.sh"

# --- Constants and Configuration ---

# Utilization thresholds for pattern classification
readonly UNDERUTILIZED_THRESHOLD=0.2    # 20% utilization
readonly HIGH_UTILIZATION_THRESHOLD=0.8  # 80% utilization
readonly NORMAL_RANGE_MIN=0.4           # 40% utilization
readonly NORMAL_RANGE_MAX=0.6           # 60% utilization

# Variation thresholds for pattern classification
readonly HIGH_VARIANCE_THRESHOLD=0.25    # 25% standard deviation
readonly LOW_VARIANCE_THRESHOLD=0.05     # 5% standard deviation

# Time windows for analysis (in hours)
readonly ANALYSIS_WINDOWS=(
    24   # 1 day
    168  # 1 week
    720  # 30 days
)

# --- Pattern Detection Functions ---

detect_resource_patterns() {
    local project_id="$1"
    local resource_id="$2"
    local resource_type="$3"
    local output_file="$4"
    
    log "INFO" "Starting pattern detection for ${resource_type}:${resource_id}"
    
    # Initialize our analysis structure
    cat > "${output_file}" << EOF
{
    "resource_id": "${resource_id}",
    "resource_type": "${resource_type}",
    "analysis_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "patterns": {
        "utilization": null,
        "trends": [],
        "seasonality": null
    },
    "recommendations": []
}
EOF
    
    # Collect and analyze metrics based on resource type
    case "${resource_type}" in
        "compute")
            analyze_compute_patterns "${project_id}" "${resource_id}" "${output_file}"
            ;;
        "storage")
            analyze_storage_patterns "${project_id}" "${resource_id}" "${output_file}"
            ;;
        "network")
            analyze_network_patterns "${project_id}" "${resource_id}" "${output_file}"
            ;;
        *)
            log "ERROR" "Unsupported resource type: ${resource_type}"
            return ${E_INVALID_INPUT}
            ;;
    esac
    
    # Generate recommendations based on detected patterns
    generate_recommendations "${output_file}"
    
    return ${E_SUCCESS}
}

analyze_compute_patterns() {
    local project_id="$1"
    local instance_id="$2"
    local output_file="$3"
    
    log "INFO" "Analyzing compute patterns for instance: ${instance_id}"
    
    # Analyze each time window to detect patterns at different scales
    for window in "${ANALYSIS_WINDOWS[@]}"; do
        local metrics
        metrics=$(get_compute_metrics "${project_id}" "${instance_id}" "${window}")
        
        # Process CPU utilization patterns
        analyze_cpu_patterns "${metrics}" "${window}" "${output_file}"
        
        # Process memory utilization patterns
        analyze_memory_patterns "${metrics}" "${window}" "${output_file}"
        
        # Look for correlations between metrics
        analyze_metric_correlations "${metrics}" "${output_file}"
    done
}

analyze_cpu_patterns() {
    local metrics="$1"
    local window="$2"
    local output_file="$3"
    
    log "DEBUG" "Analyzing CPU patterns over ${window}h window"
    
    # Calculate basic statistics
    local stats
    stats=$(calculate_metric_statistics "${metrics}" "cpu_utilization")
    
    # Extract statistical values
    local mean stddev min max
    read -r mean stddev min max <<< "${stats}"
    
    # Identify the utilization pattern
    local pattern="normal"
    local pattern_confidence=0.0
    
    # Check for underutilization
    if (( $(echo "${mean} < ${UNDERUTILIZED_THRESHOLD}" | bc -l) )); then
        pattern="underutilized"
        pattern_confidence=$(echo "1 - (${mean} / ${UNDERUTILIZED_THRESHOLD})" | bc -l)
    
    # Check for high utilization
    elif (( $(echo "${mean} > ${HIGH_UTILIZATION_THRESHOLD}" | bc -l) )); then
        pattern="overutilized"
        pattern_confidence=$(echo "(${mean} - ${HIGH_UTILIZATION_THRESHOLD}) / (1 - ${HIGH_UTILIZATION_THRESHOLD})" | bc -l)
    
    # Check for high variance
    elif (( $(echo "${stddev} > ${HIGH_VARIANCE_THRESHOLD}" | bc -l) )); then
        pattern="spiky"
        pattern_confidence=$(echo "${stddev} / (2 * ${HIGH_VARIANCE_THRESHOLD})" | bc -l)
    
    # Check for stable normal range
    elif (( $(echo "${mean} >= ${NORMAL_RANGE_MIN} && ${mean} <= ${NORMAL_RANGE_MAX}" | bc -l) )); then
        pattern="normal"
        pattern_confidence=1.0
    fi
    
    # Update the analysis file with our findings
    jq --arg window "${window}" \
       --arg pattern "${pattern}" \
       --arg confidence "${pattern_confidence}" \
       --arg mean "${mean}" \
       --arg stddev "${stddev}" \
       --arg min "${min}" \
       --arg max "${max}" \
       '.patterns.utilization.cpu += [{
           "window_hours": ($window | tonumber),
           "pattern": $pattern,
           "confidence": ($confidence | tonumber),
           "statistics": {
               "mean": ($mean | tonumber),
               "stddev": ($stddev | tonumber),
               "min": ($min | tonumber),
               "max": ($max | tonumber)
           }
       }]' "${output_file}" > "${output_file}.tmp" && \
    mv "${output_file}.tmp" "${output_file}"
}

calculate_metric_statistics() {
    local metrics="$1"
    local metric_name="$2"
    
    # Extract values and calculate statistics using awk
    echo "${metrics}" | jq -r ".[] | select(.metric == \"${metric_name}\") | .value" | \
    awk '
        BEGIN {
            sum = 0
            sum_sq = 0
            n = 0
            min = 999999
            max = -999999
        }
        {
            sum += $1
            sum_sq += $1 * $1
            if ($1 < min) min = $1
            if ($1 > max) max = $1
            n++
        }
        END {
            if (n > 0) {
                mean = sum / n
                variance = (sum_sq - (sum * sum / n)) / (n - 1)
                stddev = sqrt(variance)
                printf "%.4f %.4f %.4f %.4f", mean, stddev, min, max
            }
        }'
}

generate_recommendations() {
    local analysis_file="$1"
    
    log "INFO" "Generating recommendations based on detected patterns"
    
    # Read the detected patterns
    local patterns
    patterns=$(jq -r '.patterns.utilization' "${analysis_file}")
    
    # Initialize recommendations array
    local recommendations=()
    
    # Analyze CPU patterns
    local cpu_pattern
    cpu_pattern=$(echo "${patterns}" | jq -r '.cpu[-1].pattern')
    
    case "${cpu_pattern}" in
        "underutilized")
            recommendations+=("Consider downsizing this instance or using committed use discounts")
            recommendations+=("Evaluate workload scheduling to improve resource utilization")
            ;;
        "overutilized")
            recommendations+=("Consider upgrading instance type to handle high utilization")
            recommendations+=("Evaluate load balancing or workload distribution options")
            ;;
        "spiky")
            recommendations+=("Implement autoscaling to handle variable workloads")
            recommendations+=("Review application design for optimization opportunities")
            ;;
    esac
    
    # Update analysis file with recommendations
    jq --arg recs "$(printf '%s\n' "${recommendations[@]}")" \
       '.recommendations = ($recs | split("\n"))' \
       "${analysis_file}" > "${analysis_file}.tmp" && \
    mv "${analysis_file}.tmp" "${analysis_file}"
}

# --- Utility Functions ---

get_compute_metrics() {
    local project_id="$1"
    local instance_id="$2"
    local window="$3"
    
    # Calculate time range
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time=$(date -u -d "${window} hours ago" +"%Y-%m-%dT%H:%M:%SZ")
    
    # Fetch metrics from Cloud Monitoring
    gcloud monitoring time-series list \
        "metric.type = compute.googleapis.com/instance/cpu/utilization OR
         metric.type = compute.googleapis.com/instance/memory/utilization" \
        --filter="resource.labels.instance_id = ${instance_id}" \
        --interval="start=${start_time},end=${end_time}" \
        --format="json"
}

# --- Main Entry Point ---

main() {
    # Parse arguments
    local project_id resource_id resource_type output_file
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --resource-id)
                resource_id="$2"
                shift 2
                ;;
            --resource-type)
                resource_type="$2"
                shift 2
                ;;
            --output-file)
                output_file="$2"
                shift 2
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                return ${E_INVALID_INPUT}
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "${project_id}" || -z "${resource_id}" || \
          -z "${resource_type}" || -z "${output_file}" ]]; then
        log "ERROR" "Missing required arguments"
        return ${E_INVALID_INPUT}
    fi
    
    # Run pattern detection
    if ! detect_resource_patterns "${project_id}" "${resource_id}" \
         "${resource_type}" "${output_file}"; then
        log "ERROR" "Pattern detection failed"
        return ${E_GENERAL}
    fi
    
    return ${E_SUCCESS}
}

# Execute if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi