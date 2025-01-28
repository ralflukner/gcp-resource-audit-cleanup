#!/bin/bash

# Collect Debug Information Script
# File: gcp-debug-info.sh
# Author: Ralf B. Lukner MD PhD
# Date: 2025-01-27
# Version: 1.0

# Set output directory and file variables
OUTPUT_DIR="./debug-info"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${OUTPUT_DIR}/debug-info_${TIMESTAMP}.zip"
MISSING_INFO_FILE="${OUTPUT_DIR}/missing_info_instructions.txt"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Function to log missing information and instructions
log_missing_info() {
  local message="$1"
  echo "$message" >> "$MISSING_INFO_FILE"
  echo "$message"
}

# Start debug information collection
{
  echo "Collecting debug information..."

  # Collect last 20 lines of the execution log
  LOG_FILE="./gcp-resource-audit-cleanup.log"
  if [[ -f "$LOG_FILE" ]]; then
    echo "Adding last 20 lines of log file..."
    tail -n 20 "$LOG_FILE" > "${OUTPUT_DIR}/last_log_lines.txt"
  else
    log_missing_info "Log file not found. To manually retrieve, ensure './gcp-resource-audit-cleanup.log' exists. If it does, copy the last 20 lines into a file named 'last_log_lines.txt' and place it in the debug-info folder."
  fi

  # Collect environment variables (filtering sensitive ones)
  echo "Collecting environment variables..."
  if env | grep -E 'GCP|GOOGLE|PROJECT|REGION|ZONE' > "${OUTPUT_DIR}/environment_variables.txt"; then
    echo "Environment variables collected."
  else
    log_missing_info "Failed to collect environment variables. To retrieve manually, run 'env | grep -E \"GCP|GOOGLE|PROJECT|REGION|ZONE\"' and save the output in a file named 'environment_variables.txt' in the debug-info folder."
  fi

  # Collect active GCP configuration
  echo "Collecting GCP configuration..."
  if gcloud config list --format="text" > "${OUTPUT_DIR}/gcp_config.txt"; then
    echo "GCP configuration collected."
  else
    log_missing_info "Failed to collect GCP configuration. To retrieve manually, run 'gcloud config list --format=\"text\"' and save the output in a file named 'gcp_config.txt' in the debug-info folder."
  fi

  if gcloud auth list --format="text" > "${OUTPUT_DIR}/gcp_auth.txt"; then
    echo "GCP authentication details collected."
  else
    log_missing_info "Failed to collect GCP authentication details. To retrieve manually, run 'gcloud auth list --format=\"text\"' and save the output in a file named 'gcp_auth.txt' in the debug-info folder."
  fi

  # Check for Terraform configuration
  echo "Checking for Terraform configuration..."
  if [[ -f "./terraform.tfstate" || -d "./terraform" ]]; then
    echo "Terraform configuration detected. Adding..."
    if cp -r ./terraform* "${OUTPUT_DIR}/" 2>/dev/null; then
      echo "Terraform configuration copied."
    else
      log_missing_info "Failed to copy Terraform configuration. To retrieve manually, copy your Terraform files (e.g., 'terraform.tfstate' and related configurations) into the debug-info folder."
    fi
  else
    log_missing_info "No Terraform configuration found. If Terraform is being used, ensure your Terraform files are accessible and copy them into the debug-info folder."
  fi

  # Create a compressed debug info archive
  echo "Compressing debug information into $OUTPUT_FILE..."
  if zip -r "$OUTPUT_FILE" "$OUTPUT_DIR"/* > /dev/null; then
    echo "Debug information collected successfully: $OUTPUT_FILE"
  else
    log_missing_info "Failed to compress debug information. Please manually compress the debug-info folder and attach it to your issue report."
  fi

  echo "Debug information collection complete. Check the folder for any missing details and follow the instructions in 'missing_info_instructions.txt' if applicable."

} || {
  log_missing_info "An unexpected error occurred during debug information collection. Please review the above output for more details and manually gather any missing information as per the instructions provided."
}
