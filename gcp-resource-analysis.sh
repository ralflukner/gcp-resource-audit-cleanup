#!/opt/homebrew/bin/bash
#
# GCP Resource Analysis Module
# Version: 3.2.7
# Author: Ralf B Lukner MD PhD
#
# This module implements sophisticated analysis of GCP resources to identify
# optimization opportunities, security concerns, and cost savings potential.
# The analysis approach mirrors medical diagnostic protocols:
# - Systematic data collection (like patient history)
# - Pattern recognition (like symptom clusters)
# - Evidence-based recommendations (like treatment plans)
# - Continuous monitoring (like patient follow-up)
#
# Key Features:
# - Resource utilization analysis across multiple time windows
# - Statistical pattern detection with confidence metrics
# - Cost optimization recommendations
# - Security posture assessment
# - Performance trend analysis
#
# Dependencies:
# - gcp-utils.sh for core functionality
# - jq for JSON processing
# - bc for floating point calculations
# - awk for data analysis
#
# Change ID: CL-20250223-0017

# Source core utilities ensuring proper dependency management
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/gcp-utils.sh"

# --- Constants and Configuration ---

# Thresholds for pattern classification, based on statistical analysis
# These values were determined through empirical analysis of resource usage
readonly CPU_UNDERUTILIZED_THRESHOLD=0.1    # 10% average utilization
readonly CPU_SATURATED_THRESHOLD=0.8        # 80% average utilization
readonly MEMORY_WARNING_THRESHOLD=0.85      # 85% memory usage
readonly NETWORK_BASELINE_DEVIATION=2.0     # Standard deviations for anomaly

# Analysis time windows (in hours) for different pattern detection
readonly -a ANALYSIS_WINDOWS=(
    24    # Daily patterns
    168   # Weekly patterns
    720   # Monthly patterns
)

# --- Core Analysis Functions ---

analyze_resource_patterns() {
    local project_id="$1"
    local days_back="${2:-30}"  # Default to 30 days of history
    local output_file="${3:-${TEMP_DIR}/resource_patterns.json}"
    
    log "INFO" "Analyzing resource utilization patterns over ${days_back} days"
    
    # Initialize results structure with metadata
    # This structure follows medical record organization principles:
    # - Clear timestamps for all observations
    # - Structured categories for different types of data
    # - Space for both objective measurements and interpretations
    cat > "${output_file}" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_id": "${project_id}",
    "analysis_period_days": ${days_back},
    "patterns": {
        "compute": [],
        "storage": [],
        "networking": []
    },
    "recommendations": []
}
EOF
    
    # Analyze each resource type, similar to systems-based medical examination
    analyze_compute_patterns "${project_id}" "${days_back}" "${output_file}"
    analyze_storage_patterns "${project_id}" "${days_back}" "${output_file}"
    analyze_network_patterns "${project_id}" "${days_back}" "${output_file}"
    
    # Generate holistic recommendations, like a treatment plan
    generate_recommendations "${output_file}"
    
    return 0
}

# --- Pattern Analysis Functions ---

analyze_compute_patterns() {
    local project_id="$1"
    local days_back="$2"
    local output_file="$3"
    
    log "INFO" "Analyzing compute resource patterns"
    
    # Get compute instance inventory (like patient roster)
    local instances
    instances=$(gcloud compute instances list \
        --project="${project_id}" \
        --format="json")
    
    # Process each instance (like individual patient assessment)
    echo "${instances}" | jq -c '.[]' | while read -r instance; do
        local name zone machine_type
        name=$(echo "${instance}" | jq -r '.name')
        zone=$(echo "${instance}" | jq -r '.zone' | awk -F'/' '{print $NF}')
        machine_type=$(echo "${instance}" | jq -r '.machineType' | awk -F'/' '{print $NF}')
        
        # Collect historical metrics (like patient history)
        local metrics
        metrics=$(get_instance_metrics "${project_id}" "${name}" "${zone}" "${days_back}")
        
        # Analyze usage patterns (like symptom analysis)
        local pattern_analysis
        pattern_analysis=$(analyze_usage_pattern "${metrics}")
        
        # Update analysis results (like updating medical record)
        jq --arg name "${name}" \
           --arg zone "${zone}" \
           --arg type "${machine_type}" \
           --argjson patterns "${pattern_analysis}" \
           '.patterns.compute += [{
               "resource": $name,
               "zone": $zone,
               "type": $type,
               "usage_patterns": $patterns
           }]' "${output_file}" > "${output_file}.tmp" && \
        mv "${output_file}.tmp" "${output_file}"
    done
}

# --- Metric Collection and Analysis ---

get_instance_metrics() {
    local project_id="$1"
    local instance_name="$2"
    local zone="$3"
    local days_back="$4"
    
    # Calculate analysis time window
    local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local start_time=$(date -u -d "${days_back} days ago" +"%Y-%m-%dT%H:%M:%SZ")
    
    # Collect multiple metric types for comprehensive analysis
    # This is similar to ordering a complete set of lab tests
    local metrics
    metrics=$(gcloud monitoring time-series list \
        "metric.type = compute.googleapis.com/instance/cpu/utilization OR
         metric.type = compute.googleapis.com/instance/memory/usage OR
         metric.type = compute.googleapis.com/instance/disk/read_bytes_count OR
         metric.type = compute.googleapis.com/instance/disk/write_bytes_count OR
         metric.type = compute.googleapis.com/instance/network/received_bytes_count OR
         metric.type = compute.googleapis.com/instance/network/sent_bytes_count" \
        --filter="resource.labels.instance_id = ${instance_name}" \
        --interval="start=${start_time},end=${end_time}" \
        --format="json")
    
    echo "${metrics}"
}

analyze_usage_pattern() {
    local metrics="$1"
    
    # Initialize analysis structure for all metrics
    # This follows the principle of systematic assessment
    local pattern_analysis='{
        "cpu_pattern": null,
        "memory_pattern": null,
        "io_pattern": null,
        "network_pattern": null,
        "recommendations": []
    }'
    
    # Analyze CPU utilization patterns
    # This uses statistical analysis similar to analyzing vital signs
    local cpu_data
    cpu_data=$(echo "${metrics}" | jq -r '.[] | 
        select(.metric.type == "compute.googleapis.com/instance/cpu/utilization")')
    
    if [[ -n "${cpu_data}" ]]; then
        # Calculate comprehensive statistics
        local cpu_stats
        cpu_stats=$(echo "${cpu_data}" | jq -r '.points[] | .value.doubleValue' | \
            awk '
                BEGIN {
                    sum = 0
                    sum_sq = 0
                    n = 0
                    max = 0
                    min = 1
                }
                {
                    sum += $1
                    sum_sq += $1 * $1
                    if ($1 > max) max = $1
                    if ($1 < min) min = $1
                    n++
                }
                END {
                    mean = sum / n
                    variance = (sum_sq - (sum * sum / n)) / (n - 1)
                    printf "%.4f %.4f %.4f %.4f", mean, sqrt(variance), min, max
                }
            ')
        
        read -r mean stddev min max <<< "${cpu_stats}"
        
        # Classify usage pattern based on statistical analysis
        # This is similar to diagnostic criteria in medicine
        local pattern="unknown"
        if (( $(echo "${mean} < ${CPU_UNDERUTILIZED_THRESHOLD}" | bc -l) )); then
            pattern="underutilized"
        elif (( $(echo "${stddev} / ${mean} > 0.5" | bc -l) )); then
            pattern="spiky"
        elif (( $(echo "${mean} > ${CPU_SATURATED_THRESHOLD}" | bc -l) )); then
            pattern="saturated"
        else
            pattern="normal"
        fi
        
        # Update analysis with findings
        pattern_analysis=$(echo "${pattern_analysis}" | jq \
            --arg pattern "${pattern}" \
            --arg mean "${mean}" \
            --arg stddev "${stddev}" \
            --arg min "${min}" \
            --arg max "${max}" \
            '.cpu_pattern = {
                "pattern": $pattern,
                "statistics": {
                    "mean": ($mean | tonumber),
                    "stddev": ($stddev | tonumber),
                    "min": ($min | tonumber),
                    "max": ($max | tonumber)
                }
            }')
        
        # Generate targeted recommendations based on observed patterns
        # This is similar to treatment recommendations based on diagnosis
        case "${pattern}" in
            "underutilized")
                pattern_analysis=$(echo "${pattern_analysis}" | jq \
                    '.recommendations += ["Consider downsizing instance or using committed use discounts"]')
                ;;
            "spiky")
                pattern_analysis=$(echo "${pattern_analysis}" | jq \
                    '.recommendations += ["Consider using autoscaling or evaluating workload scheduling"]')
                ;;
            "saturated")
                pattern_analysis=$(echo "${pattern_analysis}" | jq \
                    '.recommendations += ["Consider upgrading instance or distributing workload"]')
                ;;
        esac
    fi
    
    echo "${pattern_analysis}"
}

# --- Storage Analysis ---

analyze_storage_patterns() {
    local project_id="$1"
    local days_back="$2"
    local output_file="$3"
    
    log "INFO" "Analyzing storage resource patterns"
    
    # Get storage inventory
    local buckets
    buckets=$(gcloud storage buckets list \
        --project="${project_id}" \
        --format="json")
    
    # Analyze each storage bucket
    echo "${buckets}" | jq -c '.[]' | while read -r bucket; do
        local name location storage_class
        name=$(echo "${bucket}" | jq -r '.name')
        location=$(echo "${bucket}" | jq -r '.location')
        storage_class=$(echo "${bucket}" | jq -r '.storageClass')
        
        # Collect usage statistics
        local stats
        stats=$(gsutil du -s "gs://${name}")
        
        # Analyze lifecycle configuration
        local lifecycle
        lifecycle=$(gsutil lifecycle get "gs://${name}" 2>/dev/null)
        
        # Update analysis results
        jq --arg name "${name}" \
           --arg location "${location}" \
           --arg class "${storage_class}" \
           --arg stats "${stats}" \
           --arg lifecycle "${lifecycle}" \
           '.patterns.storage += [{
               "resource": $name,
               "location": $location,
               "storage_class": $class,
               "usage_stats": $stats,
               "lifecycle_config": $lifecycle
           }]' "${output_file}" > "${output_file}.tmp" && \
        mv "${output_file}.tmp" "${output_file}"
    done
}

# --- Network Analysis ---

analyze_network_patterns() {
    local project_id="$1"
    local days_back="$2"
    local output_file="$3"
    
    log "INFO" "Analyzing network resource patterns"
    
    # Get network configuration inventory
    local networks
    networks=$(gcloud compute networks list \
        --project="${project_id}" \
        --format="json")
    
    # Analyze each network
    echo "${networks}" | jq -c '.[]' | while read -r network; do
        local name mode subnets
        name=$(echo "${network}" | jq -r '.name')
        mode=$(echo "${network}" | jq -r '.x_gcloud_mode')
        subnets=$(echo "${network}" | jq -r '.subnetworks[]' 2>/dev/null)
        
        # Analyze security configuration
        local firewall_rules
        firewall_rules=$(gcloud compute firewall-rules list \
            --filter="network=${name}" \
            --format="json")
        
        # Analyze network configuration
        local config_analysis
        config_analysis=$(analyze_network_config "${name}" "${firewall_rules}")
        
        # Update analysis results
        jq --arg name "${name}" \
           --arg mode "${mode}" \
           --argjson subnets "${subnets:-[]}" \
           --argjson config "${config_analysis}" \
           '.patterns.networking += [{
               "resource": $name,
               "mode": $mode,
               "subnets": $subnets,
               "configuration": $config
           }]' "${output_file}" > "${output_file}.tmp" && \
        mv "${output_file}.tmp" "${output_file}"
    done
}

# --- Recommendation Generation ---

generate_recommendations() {
    local analysis_file="$1"
    
    log "INFO" "Generating final recommendations"
    
    # Read complete analysis results
    local analysis
    analysis=$(cat "${analysis_file}")
    
    # Generate comprehensive recommendations
    local recommendations=()
    
    # Process compute recommendations
    local compute_patterns
    compute_patterns=$(echo "${analysis}" | jq -r '.patterns.compute[]')
    if [[ -n "${compute_patterns}" ]]; then
        while read -r pattern; do
            local resource pattern_type
            resource=$(echo "${pattern}" | jq -r '.resource')
            pattern_type=$(echo "${pattern}" | jq -r '.usage_patterns.cpu_pattern.pattern')
            
            # Generate targeted recommendations based on usage patterns
            case "${pattern_type}" in
                "underutilized")
                    recommendations+=("Consider rightsizing ${resource} to optimize costs")
                    ;;
                "spiky")
                    recommendations+=("Implement autoscaling for ${resource} to handle variable load")
                    ;;
                "saturated")
                    recommendations+=("Evaluate upgrading ${resource} to handle high load")
                    ;;
            esac
        done <<< "${compute_patterns}"
    fi
    
    # Update analysis with recommendations
    jq --arg recs "$(printf '%s\n' "${recommendations[@]}")" \
       '.recommendations = ($recs | split("\n"))' \
       "${analysis_file}" > "${analysis_file}.tmp" && \
    mv "${analysis_file}.tmp" "${analysis_file}"
}
