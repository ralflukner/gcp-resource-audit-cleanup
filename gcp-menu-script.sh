#!/opt/homebrew/bin/bash
#
# GCP Resource Audit and Cleanup Menu System
# Version: 1.1.0
# Author: Ralf B Lukner MD PhD
#
# This script provides a comprehensive, user-friendly interface to the GCP resource
# management system. It features:
#
# - Intuitive menu interface with visual status indicators
# - Project selection and status tracking
# - Comprehensive environment validation
# - Integration with test suite and resource management tools
# - Clear separation of system and project configurations
# - Detailed logging and state management
#
# The menu system maintains state between sessions, providing visual feedback about
# completed actions and project-specific operations. It uses color coding and
# visual dimming to help users track their progress and completed tasks.

# --- Global Variables and Constants ---
# Using readonly (-r) for constants to prevent accidental modification
declare -r SCRIPT_VERSION="1.1.0"
declare -r SCRIPT_NAME=$(basename "$0")
declare -r SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Core script paths - these scripts must exist for the system to function
declare -r MAIN_SCRIPT="${SCRIPT_DIR}/gcp-resource-audit-cleanup.sh"
declare -r TEST_SCRIPT="${SCRIPT_DIR}/gcp-test-suite.sh"

# Configuration and logging paths
declare -r CONFIG_DIR="${HOME}/.gcp-audit"
declare -r CONFIG_FILE="${CONFIG_DIR}/config.json"
declare -r LOG_DIR="${HOME}/gcp-logs"
declare -r LOG_FILE="${LOG_DIR}/menu_$(date +%Y%m%d_%H%M%S).log"

# Default configuration values
declare -r DEFAULT_OUTPUT_DIR="../projects-data"
declare -r DEFAULT_DAYS_IDLE=30
declare -r DEFAULT_TEST_TIMEOUT=300

# Terminal colors and formatting
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r BOLD='\033[1m'
declare -r DIM='\033[2m'
declare -r NC='\033[0m'

# --- State Management Functions ---

# Updates the completion status for various actions
update_status() {
    local status_key="$1"
    local value="$2"
    local project="${3:-}"
    
    if [[ -n "${project}" ]]; then
        # Update project-specific status and timestamp
        jq --arg key "${status_key}" \
           --arg val "${value}" \
           --arg proj "${project}" \
           --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.status.project_actions[$proj] = (
               .status.project_actions[$proj] // {}
               | .[$key] = {
                   "value": $val,
                   "timestamp": $time
               }
           )' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && \
           mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
    else
        # Update global status and timestamp
        jq --arg key "${status_key}" \
           --arg val "${value}" \
           --arg time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.status[$key] = {
               "value": $val,
               "timestamp": $time
           }' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && \
           mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
    fi
}

# Retrieves the status of a specific action
get_status() {
    local status_key="$1"
    local project="${2:-}"
    
    if [[ -n "${project}" ]]; then
        jq --arg key "${status_key}" \
           --arg proj "${project}" \
           '.status.project_actions[$proj][$key].value // "false"' \
           "${CONFIG_FILE}"
    else
        jq --arg key "${status_key}" \
           '.status[$key].value // "false"' \
           "${CONFIG_FILE}"
    fi
}

# Gets the timestamp of the last execution for an action
get_last_execution_time() {
    local status_key="$1"
    local project="${2:-}"
    
    if [[ -n "${project}" ]]; then
        jq --arg key "${status_key}" \
           --arg proj "${project}" \
           '.status.project_actions[$proj][$key].timestamp // ""' \
           "${CONFIG_FILE}"
    else
        jq --arg key "${status_key}" \
           '.status[$key].timestamp // ""' \
           "${CONFIG_FILE}"
    fi
}

# --- Display Functions ---

# Shows the main menu with visual status indicators
show_main_menu() {
    clear
    echo -e "${BOLD}=== GCP Resource Audit and Cleanup Tool ===${NC}"
    echo -e "Version: ${SCRIPT_VERSION}\n"
    
    # Display current project and its status if selected
    local current_project
    if current_project=$(cat "${CONFIG_DIR}/last_project" 2>/dev/null); then
        local last_audit
        last_audit=$(get_last_execution_time "audit_completed" "${current_project}")
        
        echo -e "${BOLD}Current Project: ${BLUE}${current_project}${NC}"
        if [[ -n "${last_audit}" && "${last_audit}" != "null" ]]; then
            echo -e "Last Audit: ${BLUE}${last_audit}${NC}\n"
        else
            echo -e "Last Audit: ${YELLOW}Never${NC}\n"
        fi
    else
        echo -e "${YELLOW}No project selected${NC}\n"
    fi
    
    # Get status values for visual indicators
    local tests_run=$(get_status "tests_completed")
    local env_check_done=$(get_status "environment_checked")
    local audit_run=$(get_status "audit_completed" "${current_project}")
    
    # Display menu items with appropriate dimming
    echo -e "1) $(format_menu_item "${tests_run}" "Run Test Suite")"
    echo -e "2) $(format_menu_item "${env_check_done}" "Run Environment Check")"
    echo -e "3) Select Project"
    echo -e "4) $(format_menu_item "${audit_run}" "Run Resource Audit")"
    echo -e "5) Analyze Resources"
    echo -e "6) Clean Up Resources"
    echo -e "7) View Project Configuration"
    echo -e "8) View System Settings"
    echo -e "9) View Logs"
    echo -e "r) Reset Status Flags"
    echo -e "q) Quit\n"
    
    echo -n "Enter selection: "
}

# Formats menu items with appropriate dimming
format_menu_item() {
    local status="$1"
    local text="$2"
    
    if [[ "${status}" == "true" ]]; then
        echo -e "${DIM}${text}${NC}"
    else
        echo -e "${text}"
    fi
}

# --- Configuration Management ---

# Initializes the configuration file with default values
initialize_configuration() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" << EOF
{
    "system": {
        "default_output_dir": "${DEFAULT_OUTPUT_DIR}",
        "default_days_idle": ${DEFAULT_DAYS_IDLE},
        "interactive_mode": true,
        "test_settings": {
            "mock_enabled": false,
            "test_timeout": ${DEFAULT_TEST_TIMEOUT},
            "verbose_testing": false
        },
        "safety_checks": {
            "require_confirmation": true,
            "backup_before_delete": true,
            "dependency_check": true
        }
    },
    "status": {
        "environment_checked": {
            "value": false,
            "timestamp": null
        },
        "tests_completed": {
            "value": false,
            "timestamp": null
        },
        "project_actions": {}
    }
}
EOF
        [[ $? -eq 0 ]] || handle_error "Failed to create configuration file"
        log "INFO" "Created default configuration file"
    fi
    
    # Validate configuration format
    if ! jq empty "${CONFIG_FILE}" 2>/dev/null; then
        handle_error "Invalid configuration file format"
    fi
}

# --- Project Management Functions ---

# Lists available GCP projects with enhanced formatting
list_projects() {
    local projects
    echo -e "\n${BLUE}Fetching available projects...${NC}"
    
    # Fetch projects with additional metadata
    if ! projects=$(gcloud projects list \
        --format="table[box](
            projectId,
            name,
            projectNumber,
            lifecycleState,
            createTime.date('%Y-%m-%d')
        )" 2>/dev/null); then
        handle_error "Failed to fetch projects. Please check your permissions."
        return 1
    fi
    
    if [[ -z "${projects}" ]]; then
        echo -e "${YELLOW}No projects found. Please check your GCP permissions.${NC}"
        return 1
    fi
    
    # Display projects with enhanced formatting
    echo -e "\n${BOLD}Available Projects:${NC}"
    echo "${projects}"
    
    return 0
}

# --- Action Functions ---

# Runs the test suite and updates status
run_test_suite() {
    local project_id
    project_id=$(cat "${CONFIG_DIR}/last_project" 2>/dev/null) || {
        handle_error "No project selected. Please select a project first."
        return 1
    }
    
    echo -e "\n${BLUE}Running test suite...${NC}"
    
    # Get test configuration
    local test_timeout
    test_timeout=$(jq -r '.system.test_settings.test_timeout' "${CONFIG_FILE}")
    
    if timeout "${test_timeout}" "${TEST_SCRIPT}" \
        --project-id="${project_id}" \
        --verbose; then
        echo -e "\n${GREEN}Test suite completed successfully.${NC}"
        update_status "tests_completed" "true"
    else
        local status=$?
        if [[ ${status} -eq 124 ]]; then
            handle_error "Test suite timed out after ${test_timeout} seconds."
        else
            handle_error "Test suite failed with status ${status}. Please check the logs."
        fi
        return 1
    fi
}

# Runs resource audit and updates project-specific status
run_resource_audit() {
    local project_id
    project_id=$(cat "${CONFIG_DIR}/last_project" 2>/dev/null) || {
        handle_error "No project selected. Please select a project first."
        return 1
    }
    
    echo -e "\n${BLUE}Running resource audit for project: ${project_id}${NC}"
    
    # Get configuration values
    local output_dir
    output_dir=$(jq -r '.system.default_output_dir' "${CONFIG_FILE}")
    
    if "${MAIN_SCRIPT}" \
        --project-id="${project_id}" \
        --output-dir="${output_dir}" \
        --verbose; then
        echo -e "\n${GREEN}Resource audit completed successfully.${NC}"
        echo -e "Results saved to: ${output_dir}/resource_inventory_*.txt"
        update_status "audit_completed" "true" "${project_id}"
    else
        handle_error "Resource audit failed. Please check the logs."
        return 1
    fi
}

# Resets all status flags
reset_status_flags() {
    echo -e "${YELLOW}This will reset all status flags. Continue? (y/N):${NC} "
    read -r response
    
    if [[ "${response}" =~ ^[Yy]$ ]]; then
        jq '.status = {
            "environment_checked": {
                "value": false,
                "timestamp": null
            },
            "tests_completed": {
                "value": false,
                "timestamp": null
            },
            "project_actions": {}
        }' "${CONFIG_FILE}" > "${CONFIG_FILE}.tmp" && \
        mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
        
        echo -e "${GREEN}Status flags have been reset.${NC}"
    fi
}

# --- Main Program Flow ---

main() {
    # Initialize environment and configuration
    initialize_environment
    
    # Register cleanup handler
    trap cleanup EXIT
    
    # Process any command line arguments
    parse_arguments "$@"
    
    # Main menu loop
    local selection
    while true; do
        show_main_menu
        read -r selection
        
        case "${selection}" in
            1)
                run_test_suite
                pause_for_user
                ;;
            2)
                check_environment
                pause_for_user
                ;;
            3)
                if list_projects; then
                    select_project
                fi
                pause_for_user
                ;;
            4)
                run_resource_audit
                pause_for_user
                ;;
            5)
                run_resource_analysis
                pause_for_user
                ;;
            6)
                run_resource_cleanup
                pause_for_user
                ;;
            7)
                view_project_configuration
                pause_for_user
                ;;
            8)
                view_system_settings
                pause_for_user
                ;;
            9)
                view_logs
                ;;
            r)
                reset_status_flags
                pause_for_user
                ;;
            q)
                echo -e "\n${GREEN}Thank you for using the GCP Resource Management Tool. Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid selection. Please try again.${NC}"
                sleep 1
                ;;
        esac
    done
}

# Execute main program if not being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi