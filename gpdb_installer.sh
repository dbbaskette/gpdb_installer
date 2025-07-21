#!/bin/bash

# Tanzu Greenplum Database Installer v2.0
# Refactored version with improved architecture and error handling

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly CONFIG_FILE="gpdb_config.conf"
readonly INSTALL_FILES_DIR="files"

# Global variables
DRY_RUN=false
PHASES=(
    "Initialization:3"
    "Pre-flight Checks:6"
    "Host Setup:3"
    "Greenplum Installation:4"
    "Completion:1"
)

# Add RESET_STATE as a global variable
RESET_STATE=false

# Add CLEAN_MODE as a global variable
CLEAN_MODE=false

# GPHOME will be set dynamically after detecting Greenplum version
# This ensures compatibility with official installation practices
GPHOME=""
export GPHOME

# Load required libraries
source "$LIB_DIR/error_handling.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/system.sh"
source "$LIB_DIR/ssh.sh"
source "$LIB_DIR/greenplum.sh"

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --dry-run       Run in dry-run mode (no actual changes)
    --config FILE   Use specific configuration file
    --help          Show this help message
    --version       Show version information
    --force         Force a fresh install (clear state markers)
    --reset         Alias for --force
    --clean         Remove Greenplum and all data directories from all hosts, then exit

EXAMPLES:
    $0                    # Run with default configuration
    $0 --dry-run          # Test run without making changes
    $0 --config custom.conf  # Use custom configuration file
    $0 --clean            # Remove Greenplum and all data on all hosts

EOF
}

# Function to show version
show_version() {
    echo "Tanzu Greenplum Database Installer v2.0"
    echo "Refactored version with improved architecture"
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
            --config)
                if [ -n "$2" ]; then
                    CONFIG_FILE="$2"
                    shift 2
                else
                    log_error "Option --config requires a filename"
                fi
                ;;
            --help)
                show_help
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --force|--reset)
                RESET_STATE=true
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Phase 1: Initialization
phase_initialization() {
    if [ -f "$STATE_DIR/.step_phase_initialization" ]; then
        log_info "Initialization phase already completed, skipping."
        return
    fi
    report_phase_start 1 "Initialization"
    
    increment_step
    report_progress "Initialization" $CURRENT_STEP 3 "Setting up environment"
    
    # Setup signal handlers
    setup_signal_handlers
    
    # Create install files directory
    mkdir -p "$INSTALL_FILES_DIR"
    log_info "Install files directory: $INSTALL_FILES_DIR"
    
    increment_step
    report_progress "Initialization" $CURRENT_STEP 3 "Loading configuration"
    
    # Configure installation
    configure_installation "$CONFIG_FILE"
    
    increment_step
    report_progress "Initialization" $CURRENT_STEP 3 "Validating configuration"
    
    # Load and validate configuration
    load_configuration "$CONFIG_FILE"
    
    report_phase_complete "Initialization"
    touch "$STATE_DIR/.step_phase_initialization"
}

# Phase 2: Pre-flight Checks
phase_preflight_checks() {
    if [ -f "$STATE_DIR/.step_phase_preflight" ]; then
        log_info "Pre-flight Checks phase already completed, skipping."
        return
    fi
    report_phase_start 2 "Pre-flight Checks"
    
    local all_hosts=($(get_all_hosts))
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking privileges"
    check_sudo_privileges
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking OS compatibility"
    check_os_compatibility "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking dependencies"
    check_dependencies "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking system resources"
    check_system_resources
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking Greenplum compatibility"
    check_greenplum_compatibility "$INSTALL_FILES_DIR"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 6 "Checking network connectivity"
    check_network_connectivity "${all_hosts[@]}"
    
    report_phase_complete "Pre-flight Checks"
    touch "$STATE_DIR/.step_phase_preflight"
}

# Phase 3: Host Setup
phase_host_setup() {
    if [ -f "$STATE_DIR/.step_phase_host_setup" ]; then
        log_info "Host Setup phase already completed, skipping."
        return
    fi
    report_phase_start 3 "Host Setup"
    
    local all_hosts=($(get_all_hosts))
    
    increment_step
    report_progress "Host Setup" $CURRENT_STEP 3 "Collecting credentials"
    collect_credentials
    
    increment_step
    report_progress "Host Setup" $CURRENT_STEP 3 "Setting up users and directories"
    setup_users_and_directories "${all_hosts[@]}"
    
    increment_step
    report_progress "Host Setup" $CURRENT_STEP 3 "Configuring SSH"
    configure_ssh_access "${all_hosts[@]}"
    
    report_phase_complete "Host Setup"
    touch "$STATE_DIR/.step_phase_host_setup"
}

# Phase 4: Greenplum Installation
phase_greenplum_installation() {
    if [ -f "$STATE_DIR/.step_phase_greenplum_installation" ]; then
        log_info "Greenplum Installation phase already completed, skipping."
        return
    fi
    report_phase_start 4 "Greenplum Installation"
    
    local all_hosts=($(get_all_hosts))
    
    increment_step
    report_progress "Greenplum Installation" $CURRENT_STEP 4 "Finding installer"
    local installer_file=$(find_greenplum_installer "$INSTALL_FILES_DIR")
    
    # Detect version and setup GPHOME
    local gp_version=$(detect_greenplum_version "$installer_file")
    setup_gphome "$gp_version"
    
    increment_step
    report_progress "Greenplum Installation" $CURRENT_STEP 4 "Distributing installer"
    distribute_installer "$installer_file" "${all_hosts[@]}"
    
    increment_step
    report_progress "Greenplum Installation" $CURRENT_STEP 4 "Installing binaries"
    install_greenplum_binaries "${all_hosts[@]}" "$installer_file"
    
    increment_step
    report_progress "Greenplum Installation" $CURRENT_STEP 4 "Initializing cluster"
    initialize_cluster
    
    report_phase_complete "Greenplum Installation"
    touch "$STATE_DIR/.step_phase_greenplum_installation"
}

# Phase 5: Completion
phase_completion() {
    if [ -f "$STATE_DIR/.step_phase_completion" ]; then
        log_info "Completion phase already completed, skipping."
        return
    fi
    report_phase_start 5 "Completion"
    
    increment_step
    report_progress "Completion" $CURRENT_STEP 1 "Final verification"
    
    # Test cluster connectivity
    if test_greenplum_connectivity "$GPDB_COORDINATOR_HOST"; then
        log_success_with_timestamp "Greenplum installation completed successfully!"
        log_info "Connect to your database with: sudo -u gpadmin psql -d tdi"
        log_info "Check cluster status with: sudo -u gpadmin gpstate -s"
    else
        log_warn "Installation completed but connectivity test failed"
        log_info "Please check the troubleshooting guide for assistance"
    fi
    
    report_phase_complete "Completion"
    touch "$STATE_DIR/.step_phase_completion"
}

# Function to collect user credentials
collect_credentials() {
    log_info "Collecting user credentials..."
    
    # Get sudo password
    read -s -p "Enter sudo password for all hosts: " SUDO_PASSWORD
    echo ""
    if [ -z "$SUDO_PASSWORD" ]; then
        log_error "Sudo password cannot be empty"
    fi
    
    # Get gpadmin password
    read -s -p "Enter password for gpadmin user: " GPADMIN_PASSWORD
    echo ""
    if [ -z "$GPADMIN_PASSWORD" ]; then
        log_error "Gpadmin password cannot be empty"
    fi
    
    # Validate password strength
    validate_password "$GPADMIN_PASSWORD" "gpadmin"
    
    log_success "Credentials collected"
}

# Function to setup users and directories
setup_users_and_directories() {
    local hosts=("$@")
    
    log_info "Setting up users and directories..."
    
    for host in "${hosts[@]}"; do
        log_info "Setting up host: $host"
        create_gpadmin_user "$host"
        if [ "$host" = "$GPDB_COORDINATOR_HOST" ]; then
            create_and_chown_dir "$host" "$COORDINATOR_DATA_DIR"
        else
            create_and_chown_dir "$host" "$SEGMENT_DATA_DIR"
        fi
    done
    
    log_success "Users and directories setup completed"
}

# Function to create gpadmin user on a host
create_gpadmin_user() {
    local host="$1"
    
    log_info "Creating gpadmin user on $host..."
    
    local remote_script="
        set -e
        if ! getent group gpadmin > /dev/null; then
            groupadd gpadmin
        fi
        
        if ! id -u gpadmin > /dev/null 2>&1; then
            useradd -g gpadmin -m -d /home/gpadmin gpadmin
        fi
        
        echo \"gpadmin:$GPADMIN_PASSWORD\" | chpasswd
        
        # Create directories
        mkdir -p \"/usr/local\" \"$GPDB_DATA_DIR\"
        chown -R gpadmin:gpadmin \"/usr/local\" \"$GPDB_DATA_DIR\"
        chmod 755 \"/usr/local\" \"$GPDB_DATA_DIR\"
    "
    
    execute_command "ssh_execute '$host' \"echo '$SUDO_PASSWORD' | sudo -S bash -c '$remote_script'\""
}

# Function to create data directories on a single host
create_data_directories_single() {
    local host="$1"
    
    log_info "Creating data directories on $host..."
    
    # Create master directory
    execute_command "ssh_execute '$host' 'sudo -u gpadmin mkdir -p $GPDB_DATA_DIR/master'"
    execute_command "ssh_execute '$host' 'sudo -u gpadmin chmod 755 $GPDB_DATA_DIR/master'"
    
    # Create segment directories
    local i=0
    for segment_host in "${GPDB_SEGMENT_HOSTS[@]}"; do
        if [ "$segment_host" = "$host" ]; then
            execute_command "ssh_execute '$host' 'sudo -u gpadmin mkdir -p $GPDB_DATA_DIR/primary$i'"
            execute_command "ssh_execute '$host' 'sudo -u gpadmin chmod 755 $GPDB_DATA_DIR/primary$i'"
        fi
        i=$((i + 1))
    done
    # After all data directories are created (in create_data_directories_single), recursively chown the parent of the data directory as well
    execute_command "ssh_execute '$host' 'sudo chown -R gpadmin:gpadmin $(dirname $GPDB_DATA_DIR)'"
}

# Function to configure SSH access
configure_ssh_access() {
    local hosts=("$@")
    
    log_info "Configuring SSH access..."
    
    if is_single_node_installation; then
        setup_single_node_ssh "gpadmin"
    else
        setup_multi_node_ssh "gpadmin" "$GPADMIN_PASSWORD" "${hosts[@]}"
    fi
    
    # Test SSH connectivity
    for host in "${hosts[@]}"; do
        if test_ssh_connectivity "gpadmin" "$host"; then
            log_success "SSH connectivity to $host verified"
        else
            log_error "SSH connectivity to $host failed"
        fi
    done
    
    log_success "SSH access configured"
}

# Function to install Greenplum binaries on all hosts
install_greenplum_binaries() {
    local hosts=("$@")
    local installer_file="${hosts[-1]}"  # Last argument is the installer file
    unset hosts[-1]  # Remove installer file from hosts array
    
    log_info "Installing Greenplum binaries..."
    
    for host in "${hosts[@]}"; do
        install_greenplum_single "$host" "$installer_file" "$SUDO_PASSWORD"
    done
    
    log_success "Greenplum binaries installed on all hosts"
}

# Function to initialize the cluster
initialize_cluster() {
    local all_hosts=($(get_all_hosts))
    
    log_info "Initializing Greenplum cluster..."
    
    # Generate configuration
    local config_file=$(generate_gpinitsystem_config "$GPDB_COORDINATOR_HOST" "${GPDB_SEGMENT_HOSTS[@]}")
    local machine_list_file="/tmp/machine_list"
    
    # Create data directories
    create_data_directories "${all_hosts[@]}"
    
    # Initialize cluster
    initialize_greenplum_cluster "$GPDB_COORDINATOR_HOST" "$config_file" "$machine_list_file"
    
    # Setup environment
    setup_gpadmin_environment "${all_hosts[@]}"
    
    # Configure pg_hba.conf
    configure_pg_hba "$GPDB_COORDINATOR_HOST" "${all_hosts[@]}"
    
    # Restart cluster
    restart_greenplum_cluster "$GPDB_COORDINATOR_HOST"
    
    log_success "Cluster initialization completed"
}

# Function to clean Greenplum and data directories
clean_greenplum() {
    local all_hosts=($(get_all_hosts))
    log_warn "CLEAN MODE: This will remove Greenplum and all data directories from all hosts!"
    for host in "${all_hosts[@]}"; do
        log_info "[CLEAN] Removing data directory $GPDB_DATA_DIR on $host..."
        execute_command "ssh_execute '$host' 'sudo rm -rf $GPDB_DATA_DIR'"
        log_info "[CLEAN] Attempting to remove parent directory $(dirname $GPDB_DATA_DIR) on $host (if empty)..."
        execute_command "ssh_execute '$host' 'sudo rmdir $(dirname $GPDB_DATA_DIR) 2>/dev/null || true'"
        log_info "[CLEAN] Uninstalling Greenplum on $host..."
        execute_command "ssh_execute '$host' 'sudo yum remove -y greenplum-db-7'"
    done
    log_success "Greenplum and all data directories removed from all hosts."
}

# Function to create and chown a directory
create_and_chown_dir() {
    local host="$1"
    local dir="$2"
    execute_command "ssh_execute '$host' 'sudo mkdir -p $dir && sudo chown -R gpadmin:gpadmin $dir'"
}

# Function to generate gpinitsystem_config
generate_gpinitsystem_config() {
    local coordinator_host="$1"
    shift
    local segment_hosts=("$@")
    local config_file="/tmp/gpinitsystem_config"
    echo "ARRAY_NAME=\"TDI Greenplum Cluster\"" > "$config_file"
    echo "SEG_PREFIX=gpseg" >> "$config_file"
    echo "PORT_BASE=40000" >> "$config_file"
    echo "COORDINATOR_HOSTNAME=$coordinator_host" >> "$config_file"
    echo "COORDINATOR_DIRECTORY=$COORDINATOR_DATA_DIR" >> "$config_file"
    echo "COORDINATOR_PORT=5432" >> "$config_file"
    echo "DATABASE_NAME=tdi" >> "$config_file"
    echo "ENCODING=UNICODE" >> "$config_file"
    echo "LOCALE=en_US.utf8" >> "$config_file"
    echo "CHECK_POINT_SEGMENTS=8" >> "$config_file"
    # DATA_DIRECTORY array for segments
    echo -n "declare -a DATA_DIRECTORY=(" >> "$config_file"
    for host in "${segment_hosts[@]}"; do
        echo -n "$SEGMENT_DATA_DIR " >> "$config_file"
    done
    echo ")" >> "$config_file"
    echo "$config_file"
}

# Function to initialize the cluster
initialize_greenplum_cluster() {
    local coordinator_host="$1"
    local config_file="$2"
    local machine_list_file="$3"
    execute_command ssh "$coordinator_host" "source /usr/local/greenplum-db/greenplum_path.sh && export COORDINATOR_DATA_DIRECTORY=$COORDINATOR_DATA_DIR && gpinitsystem -c $config_file -h $machine_list_file"
}

# Main execution function
main() {
    echo -e "${COLOR_GREEN}Tanzu Greenplum Database Installer v2.0${COLOR_RESET}"
    log_info_with_timestamp "Starting installation process"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    STATE_DIR="/tmp/gpdb_installer_state"
    mkdir -p "$STATE_DIR"
    if [ "$CLEAN_MODE" = true ]; then
        clean_greenplum
        exit 0
    fi
    if [ "$RESET_STATE" = true ]; then
        echo "[INFO] Clearing all step markers in $STATE_DIR..."
        rm -f $STATE_DIR/.step_*
    fi
    
    # Execute installation phases
    phase_initialization
    phase_preflight_checks
    phase_host_setup
    phase_greenplum_installation
    phase_completion
    
    log_success_with_timestamp "Installation completed successfully!"
}

# Execute main function with all arguments
main "$@"