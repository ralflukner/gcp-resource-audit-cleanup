#!/bin/bash

# Format resource utilization report with ASCII charts and tables
format_resource_report() {
    local report_file="$1"
    local output_file="$2"
    
    # Initialize the report with a header
    cat << EOF > "${output_file}"
=================================================================
                  GCP Resource Analysis Report                    
                  Generated: $(date '+%Y-%m-%d %H:%M:%S')
=================================================================

EOF

    # Format compute resource utilization section
    format_compute_utilization "${report_file}" >> "${output_file}"
    echo >> "${output_file}"  # Add spacing

    # Format storage utilization section
    format_storage_utilization "${report_file}" >> "${output_file}"
    echo >> "${output_file}"  # Add spacing

    # Format recommendations section
    format_recommendations "${report_file}" >> "${output_file}"
}

# Format compute resource utilization with ASCII bar charts
format_compute_utilization() {
    local report_file="$1"
    
    echo "COMPUTE RESOURCE UTILIZATION"
    echo "==========================="
    echo
    
    # Read compute metrics from report
    local instances
    instances=$(jq -r '.resources.instances[]' "${report_file}")
    
    # Calculate maximum name length for padding
    local max_name_length=0
    while IFS= read -r instance; do
        local name
        name=$(echo "${instance}" | jq -r '.name')
        if (( ${#name} > max_name_length )); then
            max_name_length=${#name}
        fi
    done <<< "${instances}"
    
    # Print utilization bars
    while IFS= read -r instance; do
        local name cpu_util memory_util status
        name=$(echo "${instance}" | jq -r '.name')
        cpu_util=$(echo "${instance}" | jq -r '.average_cpu')
        memory_util=$(echo "${instance}" | jq -r '.memory_usage // "0"')
        status=$(echo "${instance}" | jq -r '.status')
        
        # Convert decimal to integer percentage
        local cpu_percent memory_percent
        cpu_percent=$(printf "%.0f" "$(echo "${cpu_util} * 100" | bc)")
        memory_percent=$(printf "%.0f" "$(echo "${memory_util} * 100" | bc)")
        
        # Create the bars
        printf "%-${max_name_length}s " "${name}"
        
        # CPU utilization bar
        printf "CPU: ["
        local bar_length=50
        local filled_length=$(( cpu_percent * bar_length / 100 ))
        local i
        for ((i = 0; i < filled_length; i++)); do
            printf "#"
        done
        for ((i = filled_length; i < bar_length; i++)); do
            printf " "
        done
        printf "] %3d%%\n" "${cpu_percent}"
        
        # Memory utilization bar
        printf "%${max_name_length}s " ""  # Padding for alignment
        printf "MEM: ["
        filled_length=$(( memory_percent * bar_length / 100 ))
        for ((i = 0; i < filled_length; i++)); do
            printf "#"
        done
        for ((i = filled_length; i < bar_length; i++)); do
            printf " "
        done
        printf "] %3d%%\n" "${memory_percent}"
        
        # Status indicator
        printf "%${max_name_length}s %s\n" "" "Status: ${status}"
        echo
    done <<< "${instances}"
}

# Format storage utilization with ASCII tables
format_storage_utilization() {
    local report_file="$1"
    
    echo "STORAGE RESOURCE UTILIZATION"
    echo "==========================="
    echo
    
    # Print header
    printf "%-30s %-15s %-15s %-15s\n" "Bucket Name" "Size (GB)" "Class" "Last Access"
    printf "%-30s %-15s %-15s %-15s\n" "$(printf '%.30s' "$(printf '%75s' | tr ' ' '-')")" \
        "$(printf '%.15s' "$(printf '%15s' | tr ' ' '-')")" \
        "$(printf '%.15s' "$(printf '%15s' | tr ' ' '-')")" \
        "$(printf '%.15s' "$(printf '%15s' | tr ' ' '-')")"
    
    # Read and format storage data
    jq -r '.resources.storage[] | [.name, (.size_bytes/1024/1024/1024|floor), .storage_class, .last_access] | @tsv' \
        "${report_file}" | \
    while IFS=$'\t' read -r name size class access; do
        printf "%-30.30s %-15.2f %-15s %-15s\n" "${name}" "${size}" "${class}" "${access}"
    done
    echo
}

# Format recommendations in an easy-to-read list
format_recommendations() {
    local report_file="$1"
    
    echo "OPTIMIZATION RECOMMENDATIONS"
    echo "=========================="
    echo
    
    # Read and format recommendations
    local count=1
    jq -r '.recommendations[]' "${report_file}" | while IFS= read -r recommendation; do
        printf "%2d. %s\n" "${count}" "${recommendation}"
        count=$((count + 1))
    done
}

# Example usage:
# format_resource_report "analysis_report.json" "formatted_report.txt"

# Sample output will look like:
#
# COMPUTE RESOURCE UTILIZATION
# ===========================
# instance-1   CPU: [####################                    ] 40%
#              MEM: [########################                ] 50%
#              Status: normal
#
# instance-2   CPU: [##########                              ] 20%
#              MEM: [###########                             ] 22%
#              Status: underutilized
#
# STORAGE RESOURCE UTILIZATION
# ===========================
# Bucket Name                    Size (GB)      Class          Last Access
# ------------------------------ --------------- --------------- ---------------
# bucket-1                       1,024.00       STANDARD       2024-01-20
# bucket-2                       2,048.00       NEARLINE       2023-12-15
#
# OPTIMIZATION RECOMMENDATIONS
# ==========================
# 1. Consider rightsizing instance-2 due to consistent low utilization
# 2. Evaluate storage class transition for bucket-1 based on access patterns