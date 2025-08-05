#!/bin/bash

# Greenplum Cleanup Script
# Removes Greenplum installation, data directories, and gpadmin user data
# Uses existing configuration to determine hosts and directories

set -eE

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly CONFIG_FILE="gpdb_config.conf"

# Load required libraries
if [ -f "$LIB_DIR/logging.sh" ]; then
    source "$LIB_DIR/logging.sh"
else
    # Fallback logging
    log_info() { echo "[INFO] $1"; }
    log_success() { echo "[SUCCESS] $1"; }
    log_warn() { echo "[WARN] $1"; }
    log_error() { echo "[ERROR] $1" >&2; }
fi

if [ -f "$LIB_DIR/config.sh" ]; then
    source "$LIB_DIR/config.sh"
fi

if [ -f "$LIB_DIR/ssh.sh" ]; then
    source "$LIB_DIR/ssh.sh"
fi

# Global variables
DRY_RUN=false
FORCE=false
VERBOSE=false
CLEAN_INSTALLER=true

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Greenplum Cleanup Script - Removes Greenplum installation and data

OPTIONS:
    --dry-run           Show what would be cleaned without doing it
    --force             Force cleanup without confirmation prompts
    --verbose           Enable verbose output
    --help              Show this help message
    --keep-installer    Keep installer scripts and only clean Greenplum components

CLEANUP ACTIONS:
    1. Stop all Greenplum processes on all hosts
    2. Remove all data directories (coordinator, primary, mirror)
    3. Clean gpadmin home directory (except the directory itself)
    4. Uninstall Greenplum RPM packages
    5. Clean up shared memory and semaphores
    6. Remove Greenplum installation directories

REQUIREMENTS:
    - SSH access to all configured hosts
    - sudo privileges on all hosts
    - Existing gpdb_config.conf file

EXAMPLES:
    $0                  # Interactive cleanup
    $0 --dry-run        # Test what would be cleaned
    $0 --force          # Clean without prompts
    $0 --verbose        # Detailed cleanup output

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                log_warn "Dry run mode enabled. No commands will be executed."
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --keep-installer)
                CLEAN_INSTALLER=false
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to get all hosts from configuration
get_all_hosts_from_config() {
    local hosts=()
    
    # Load configuration if available
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE" 2>/dev/null || true
        
        # Add coordinator host
        if [ -n "$GPDB_COORDINATOR_HOST" ]; then
            hosts+=("$GPDB_COORDINATOR_HOST")
        fi
        
        # Add segment hosts
        if [ ${#GPDB_SEGMENT_HOSTS[@]} -gt 0 ]; then
            hosts+=("${GPDB_SEGMENT_HOSTS[@]}")
        fi
        
        # Add standby host if configured
        if [ -n "$GPDB_STANDBY_HOST" ]; then
            hosts+=("$GPDB_STANDBY_HOST")
        fi
    else
        log_error "Configuration file not found: $CONFIG_FILE"
        log_error "Please ensure you're running this script from the installer directory"
        exit 1
    fi
    
    # Remove duplicates
    local unique_hosts=($(printf "%s\n" "${hosts[@]}" | sort -u))
    echo "${unique_hosts[@]}"
}

# Function to confirm cleanup action
confirm_cleanup() {
    if [ "$FORCE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    echo ""
    log_warn "This will completely remove Greenplum and all data from the following hosts:"
    local all_hosts=($(get_all_hosts_from_config))
    for host in "${all_hosts[@]}"; do
        echo "  - $host"
    done
    echo ""
    log_warn "This action is IRREVERSIBLE and will:"
    echo "  - Stop all Greenplum processes"
    echo "  - Remove all data directories and their contents"
    echo "  - Clean gpadmin home directory"
    echo "  - Uninstall Greenplum RPM packages"
    echo "  - Remove Greenplum installation directories"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [ "$confirmation" != "yes" ]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to execute command with dry run support
execute_cleanup_command() {
    local host="$1"
    local command="$2"
    local description="$3"
    
    if [ "$VERBOSE" = true ]; then
        log_info "[$host] $description"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] [$host] Would execute: $command"
        return 0
    else
        if ssh_execute "$host" "$command" 2>/dev/null; then
            if [ "$VERBOSE" = true ]; then
                log_success "[$host] $description completed"
            fi
            return 0
        else
            log_warn "[$host] $description failed (continuing anyway)"
            return 0  # Don't fail the entire cleanup for individual command failures
        fi
    fi
}

# Function to stop Greenplum processes on a host
stop_greenplum_processes() {
    local host="$1"
    
    log_info "[$host] Stopping Greenplum processes..."
    
    local stop_commands="
        # Stop Greenplum cluster gracefully (if running)
        sudo -u gpadmin bash -c 'source /usr/local/greenplum-db/greenplum_path.sh 2>/dev/null && gpstop -a -M fast' 2>/dev/null || true
        
        # Kill any remaining Greenplum processes
        pkill -f 'postgres.*gp' 2>/dev/null || true
        pkill -f 'gpsync' 2>/dev/null || true
        pkill -f 'gpmmon' 2>/dev/null || true
        pkill -f 'gpsmon' 2>/dev/null || true
        pkill -f 'gpfdist' 2>/dev/null || true
        pkill -f 'gpload' 2>/dev/null || true
        
        # Kill any postgres processes owned by gpadmin
        pkill -u gpadmin 2>/dev/null || true
        
        # Wait a moment for processes to terminate
        sleep 2
        
        # Force kill if needed
        pkill -9 -f 'postgres.*gp' 2>/dev/null || true
        pkill -9 -u gpadmin 2>/dev/null || true
    "
    
    execute_cleanup_command "$host" "$stop_commands" "Stop Greenplum processes"
}

# Function to clean data directories on a host
clean_data_directories() {
    local host="$1"
    
    log_info "[$host] Cleaning data directories..."
    
    # Get data root from config
    local data_root="${GPDB_DATA_ROOT:-/home/gpdata}"
    
    local cleanup_commands="
        # Remove all data directories completely
        rm -rf '$data_root' 2>/dev/null || true
        rm -rf /data/coordinator /data/primary /data/mirror 2>/dev/null || true
        rm -rf /home/gpdata 2>/dev/null || true
        rm -rf /usr/local/greenplum-db-data 2>/dev/null || true
        
        # Clean up any other common data locations
        rm -rf /tmp/greenplum* 2>/dev/null || true
        rm -rf /tmp/gp* 2>/dev/null || true
        rm -rf /var/log/greenplum* 2>/dev/null || true
        
        # Clean up installer temp files
        rm -f /tmp/gpinitsystem_config /tmp/machine_list 2>/dev/null || true
    "
    
    execute_cleanup_command "$host" "$cleanup_commands" "Clean data directories"
}

# Function to clean gpadmin home directory
clean_gpadmin_home() {
    local host="$1"
    
    log_info "[$host] Cleaning gpadmin home directory..."
    
    local cleanup_commands="
        # Remove all contents from gpadmin home but keep the directory
        if [ -d /home/gpadmin ]; then
            rm -rf /home/gpadmin/* 2>/dev/null || true
            rm -rf /home/gpadmin/.* 2>/dev/null || true
            # Recreate essential dot files
            sudo -u gpadmin touch /home/gpadmin/.bashrc
            sudo -u gpadmin touch /home/gpadmin/.bash_profile
            chown gpadmin:gpadmin /home/gpadmin/.bashrc /home/gpadmin/.bash_profile
        fi
    "
    
    execute_cleanup_command "$host" "$cleanup_commands" "Clean gpadmin home directory"
}

# Function to uninstall Greenplum packages
uninstall_greenplum_packages() {
    local host="$1"
    
    log_info "[$host] Uninstalling Greenplum packages..."
    
    local uninstall_commands="
        # Remove Greenplum RPM packages
        yum remove -y greenplum-db-7 greenplum-db greenplum-* 2>/dev/null || true
        rpm -e greenplum-db-7 2>/dev/null || true
        rpm -e greenplum-db 2>/dev/null || true
        
        # Remove installation directories
        rm -rf /usr/local/greenplum-db* 2>/dev/null || true
        rm -rf /usr/local/greenplum 2>/dev/null || true
        
        # Clean up any remaining files
        find /usr/local -name '*greenplum*' -type d -exec rm -rf {} + 2>/dev/null || true
        find /usr/local -name '*greenplum*' -type f -delete 2>/dev/null || true
    "
    
    execute_cleanup_command "$host" "$uninstall_commands" "Uninstall Greenplum packages"
}

# Function to clean shared memory and semaphores
clean_shared_memory() {
    local host="$1"
    
    log_info "[$host] Cleaning shared memory and semaphores..."
    
    local cleanup_commands="
        # Remove shared memory segments owned by gpadmin
        ipcs -m | grep gpadmin | awk '{print \$2}' | xargs -r ipcrm -m 2>/dev/null || true
        
        # Remove semaphore sets owned by gpadmin
        ipcs -s | grep gpadmin | awk '{print \$2}' | xargs -r ipcrm -s 2>/dev/null || true
        
        # Remove message queues owned by gpadmin
        ipcs -q | grep gpadmin | awk '{print \$2}' | xargs -r ipcrm -q 2>/dev/null || true
        
        # Clean up any PostgreSQL shared memory
        ipcs -m | grep postgres | awk '{print \$2}' | xargs -r ipcrm -m 2>/dev/null || true
        ipcs -s | grep postgres | awk '{print \$2}' | xargs -r ipcrm -s 2>/dev/null || true
    "
    
    execute_cleanup_command "$host" "$cleanup_commands" "Clean shared memory and semaphores"
}

# Function to cleanup single host
cleanup_host() {
    local host="$1"
    
    log_info "Starting cleanup on $host..."
    
    # Stop Greenplum processes first
    stop_greenplum_processes "$host"
    
    # Clean data directories
    clean_data_directories "$host"
    
    # Clean gpadmin home
    clean_gpadmin_home "$host"
    
    # Uninstall packages
    uninstall_greenplum_packages "$host"
    
    # Clean shared memory
    clean_shared_memory "$host"
    
    log_success "Cleanup completed on $host"
}

# Function to establish SSH connections to all hosts
establish_ssh_connections() {
    local hosts=("$@")
    
    log_info "Establishing SSH connections to all hosts..."
    
    for host in "${hosts[@]}"; do
        if ! establish_ssh_connection "$host" 2>/dev/null; then
            log_warn "Could not establish SSH master connection to $host (will use regular SSH)"
        fi
    done
}

# Main cleanup function
main() {
    echo -e "\033[0;32mGreenplum Cleanup Script\033[0m"
    echo "========================================"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Get all hosts from configuration
    local all_hosts=($(get_all_hosts_from_config))
    
    if [ ${#all_hosts[@]} -eq 0 ]; then
        log_error "No hosts found in configuration"
        exit 1
    fi
    
    log_info "Configuration loaded successfully"
    log_info "Hosts to clean: ${all_hosts[*]}"
    
    if [ -n "$GPDB_DATA_ROOT" ]; then
        log_info "Data root directory: $GPDB_DATA_ROOT"
    fi
    
    # Confirm cleanup
    confirm_cleanup
    
    # Collect SSH password if needed for better performance
    if ! [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        read -p "Do all hosts use the same SSH password? (y/n) [y]: " same_ssh_password
        same_ssh_password=${same_ssh_password:-y}
        
        if [[ "$same_ssh_password" =~ ^[Yy]$ ]]; then
            read -s -p "Enter SSH password for all hosts: " SSH_PASSWORD
            echo ""
            export SSH_PASSWORD
            export SSHPASS="$SSH_PASSWORD"
            log_success "SSH password will be used for all hosts"
        fi
        
        # Clean up any existing SSH connections first
        if declare -f cleanup_all_ssh_connections > /dev/null; then
            cleanup_all_ssh_connections
            cleanup_remote_ssh_connections "${all_hosts[@]}"
        fi
        establish_ssh_connections "${all_hosts[@]}"
    fi
    
    # Perform cleanup on all hosts
    log_info "Starting comprehensive Greenplum cleanup..."
    
    for host in "${all_hosts[@]}"; do
        cleanup_host "$host"
    done
    
    # Clean up SSH connections
    if declare -f cleanup_ssh_connections > /dev/null; then
        cleanup_ssh_connections
    fi
    
    # Clean up installer directory (but preserve RPM files)
    if [ "$CLEAN_INSTALLER" = true ]; then
        log_info "Cleaning up installer directory (preserving RPM files)..."
        if [ -d "$SCRIPT_DIR" ] && [[ "$SCRIPT_DIR" == *gpdb_installer* ]]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY-RUN] Would clean installer directory: $SCRIPT_DIR"
                log_info "[DRY-RUN] Would preserve files/ directory with RPMs"
            else
                # Save the files directory if it exists
                if [ -d "$SCRIPT_DIR/files" ]; then
                    log_info "Backing up files/ directory temporarily..."
                    mv "$SCRIPT_DIR/files" "/tmp/gpdb_installer_files_backup" 2>/dev/null || true
                fi
                
                # Clean up everything in the installer directory except files/
                log_info "Removing installer scripts and generated files..."
                find "$SCRIPT_DIR" -mindepth 1 -maxdepth 1 ! -name "files" -exec rm -rf {} + 2>/dev/null || true
                
                # Restore the files directory
                if [ -d "/tmp/gpdb_installer_files_backup" ]; then
                    log_info "Restoring files/ directory..."
                    mv "/tmp/gpdb_installer_files_backup" "$SCRIPT_DIR/files" 2>/dev/null || true
                fi
                
                log_success "Installer directory cleaned (files/ directory preserved)"
            fi
        else
            log_warn "Installer directory not found or invalid path: $SCRIPT_DIR"
        fi
    else
        log_info "Skipping installer directory cleanup (--keep-installer specified)"
    fi
    
    echo ""
    log_success "Greenplum cleanup completed successfully on all hosts!"
    
    if [ "$DRY_RUN" = true ]; then
        echo ""
        log_info "This was a dry run. No actual changes were made."
        log_info "Run without --dry-run to perform the actual cleanup."
    else
        echo ""
        log_info "All Greenplum components have been removed from:"
        for host in "${all_hosts[@]}"; do
            echo "  - $host"
        done
        echo ""
        log_info "You can now run a fresh installation if desired."
    fi
}

# Execute main function with all arguments
main "$@"