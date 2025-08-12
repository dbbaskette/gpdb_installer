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
    "Pre-flight Checks:8"
    "Host Setup:2"
    "Greenplum Installation:4"
    "PXF Installation:4"
    "Extensions Installation:4"
    "Completion:1"
)

# Add RESET_STATE as a global variable
RESET_STATE=false

# Add CLEAN_MODE as a global variable
CLEAN_MODE=false
EXTENSIONS_ONLY=false
CLI_INSTALL_MADLIB=false
CLI_INSTALL_POSTGIS=false
CLI_INSTALL_SPARK_CONNECTOR=false

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
source "$LIB_DIR/pxf.sh"
source "$LIB_DIR/madlib.sh"
source "$LIB_DIR/postgis.sh"
source "$LIB_DIR/spark.sh"

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
    --install-madlib            Install MADlib only (skips GP/PXF phases)
    --install-postgis          Install PostGIS only (skips GP/PXF phases)
    --install-spark-connector  Install Greenplum Spark Connector only (skips GP/PXF phases)
    --extensions-only          Run only the extensions phase (honors config flags)

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
            --install-madlib)
                INSTALL_MADLIB=true
                CLI_INSTALL_MADLIB=true
                EXTENSIONS_ONLY=true
                shift
                ;;
            --install-postgis)
                INSTALL_POSTGIS=true
                CLI_INSTALL_POSTGIS=true
                EXTENSIONS_ONLY=true
                shift
                ;;
            --install-spark-connector)
                INSTALL_SPARK_CONNECTOR=true
                CLI_INSTALL_SPARK_CONNECTOR=true
                EXTENSIONS_ONLY=true
                shift
                ;;
            --extensions-only)
                EXTENSIONS_ONLY=true
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
        # Still need to load configuration even if initialization was skipped
        load_configuration "$CONFIG_FILE"
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
        # Ensure configuration is loaded
        load_configuration "$CONFIG_FILE" 2>/dev/null || true
        return
    fi
    report_phase_start 2 "Pre-flight Checks"
    
    local all_hosts=($(get_all_hosts))
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Collecting credentials"
    collect_credentials
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Establishing SSH connections"
    # Clean up any existing SSH connections first to start fresh
    cleanup_all_ssh_connections
    cleanup_remote_ssh_connections "${all_hosts[@]}"
    log_info "Establishing SSH master connections to avoid repeated password prompts..."
    establish_ssh_connections "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking privileges on remote hosts"
    check_remote_sudo_privileges "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking OS compatibility"
    check_os_compatibility "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking dependencies"
    check_dependencies "${all_hosts[@]}"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking system resources"
    check_system_resources
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking Greenplum compatibility"
    check_greenplum_compatibility "$INSTALL_FILES_DIR"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 8 "Checking network connectivity"
    check_network_connectivity "${all_hosts[@]}"
    
    report_phase_complete "Pre-flight Checks"
    touch "$STATE_DIR/.step_phase_preflight"
}

# Phase 3: Host Setup
phase_host_setup() {
    if [ -f "$STATE_DIR/.step_phase_host_setup" ]; then
        log_info "Host Setup phase already completed, skipping."
        # Ensure configuration is loaded
        load_configuration "$CONFIG_FILE" 2>/dev/null || true
        return
    fi
    report_phase_start 3 "Host Setup"
    
    local all_hosts=($(get_all_hosts))
    
    increment_step
    report_progress "Host Setup" $CURRENT_STEP 2 "Setting up users and directories"
    setup_users_and_directories "${all_hosts[@]}"
    
    increment_step
    report_progress "Host Setup" $CURRENT_STEP 2 "Configuring SSH and firewall"
    configure_ssh_access "${all_hosts[@]}"
    configure_greenplum_firewall "${all_hosts[@]}"
    
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
    
    # Ensure SSH connections are still available before starting installation
    ensure_ssh_connections "${all_hosts[@]}"
    
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

# Phase 5: PXF Installation
phase_pxf_installation() {
    if [ -f "$STATE_DIR/.step_phase_pxf_installation" ]; then
        log_info "PXF Installation phase already completed, skipping."
        return
    fi
    
    # Check if PXF should be installed
    if ! should_install_pxf; then
        log_info "PXF installation skipped (not configured or PXF installer not found)"
        touch "$STATE_DIR/.step_phase_pxf_installation"
        return
    fi
    
    report_phase_start 5 "PXF Installation"
    
    local all_hosts=($(get_all_hosts))
    
    # Ensure SSH connections are still available
    ensure_ssh_connections "${all_hosts[@]}"
    
    increment_step
    report_progress "PXF Installation" $CURRENT_STEP 4 "Finding PXF installer"
    log_info "Looking for PXF installer in '$INSTALL_FILES_DIR'..."
    
    # Find PXF installer (separate from logging to avoid output capture)
    local pxf_installer_file
    if ! pxf_installer_file=$(find_pxf_installer "$INSTALL_FILES_DIR"); then
        log_warn "PXF installer not found, skipping PXF installation"
        touch "$STATE_DIR/.step_phase_pxf_installation"
        return
    fi
    
    # Verify we got a clean file path (no log contamination)
    if [[ "$pxf_installer_file" == *"[INFO]"* ]] || [[ "$pxf_installer_file" == *$'\033'* ]]; then
        log_error "PXF installer path contaminated with log output: $pxf_installer_file"
        return 1
    fi
    
    log_success "Found PXF installer: $pxf_installer_file"
    
    increment_step
    report_progress "PXF Installation" $CURRENT_STEP 4 "Installing PXF binaries (root operations)"
    
    # Group all ROOT operations together to minimize password prompts
    log_info "Performing all root-level PXF operations..."
    
    # 1. Distribute installer
    distribute_pxf_installer "$pxf_installer_file" "${all_hosts[@]}"
    
    # 2. Install PXF binaries
    install_pxf_binaries "${all_hosts[@]}" "$pxf_installer_file"
    
    # 3. Configure PXF services on all hosts  
    for host in "${all_hosts[@]}"; do
        configure_pxf_service "$host" "$SUDO_PASSWORD"
    done
    
    # 4. Setup PXF environment
    setup_pxf_environment "${all_hosts[@]}"
    
    # 5. Setup Java environment on all hosts (critical for PXF)
    log_info "Setting up Java environment for PXF on all hosts..."
    setup_java_environment "${all_hosts[@]}"
    
    # 6. Fix PXF directory ownership on all hosts
    log_info "Setting PXF directory ownership..."
    for host in "${all_hosts[@]}"; do
        ssh_execute "$host" "chown -R gpadmin:gpadmin /usr/local/pxf-gp7" "" "false" "root"
    done
    
    log_success "All root-level PXF operations completed"
    
    increment_step
    report_progress "PXF Installation" $CURRENT_STEP 4 "PXF cluster setup (gpadmin operations)" 
    
    # Refresh SSH connections before gpadmin operations
    refresh_ssh_connections "${all_hosts[@]}"
    
    # Group all GPADMIN operations together to minimize password prompts
    log_info "Performing all gpadmin-level PXF operations..."
    
    # 1. Verify Greenplum is ready for PXF (as gpadmin)
    verify_greenplum_for_pxf "$GPDB_COORDINATOR_HOST"
    
    # 2. Initialize PXF cluster
    initialize_pxf_cluster "$GPDB_COORDINATOR_HOST"
    
    # 2a. Distribute PXF extension files to all hosts (needed for segments)
    distribute_pxf_extension_files "${all_hosts[@]}"
    
    # 3. Enable PXF extension in database
    enable_pxf_extension "$GPDB_COORDINATOR_HOST" "tdi"
    
    # 4. Test PXF installation
    test_pxf_installation "$GPDB_COORDINATOR_HOST"
    
    increment_step
    report_progress "PXF Installation" $CURRENT_STEP 4 "Verifying PXF configuration"
    
    # Verify and fix PXF configuration (integrated from fix scripts)
    verify_and_fix_pxf_configuration "$GPDB_COORDINATOR_HOST"
    
    log_success "All gpadmin-level PXF operations completed"
    
    report_phase_complete "PXF Installation"
    touch "$STATE_DIR/.step_phase_pxf_installation"
}

# Phase 6: Extensions (MADlib, PostGIS, Spark Connector)
phase_extensions_installation() {
    if [ -f "$STATE_DIR/.step_phase_extensions_installation" ]; then
        log_info "Extensions Installation phase already completed, skipping."
        return
    fi

    report_phase_start 6 "Extensions Installation"

    local all_hosts=($(get_all_hosts))

    # Ensure SSH connections are still available
    ensure_ssh_connections "${all_hosts[@]}"

    # MADlib
    if should_install_madlib && { [ "$EXTENSIONS_ONLY" != true ] || [ "$CLI_INSTALL_MADLIB" = true ]; }; then
        increment_step
        report_progress "Extensions Installation" $CURRENT_STEP 4 "Installing MADlib"
        local madlib_installer
        if madlib_installer=$(find_madlib_installer "$INSTALL_FILES_DIR"); then
            distribute_madlib_installer "$madlib_installer" "${all_hosts[@]}"
            install_madlib_binaries "${all_hosts[@]}" "$madlib_installer"
            enable_madlib_extension "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
            verify_madlib_installation "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
        else
            log_warn "MADlib installer not found; skipping"
        fi
    else
        log_info "MADlib installation skipped"
    fi

    # PostGIS
    if should_install_postgis && { [ "$EXTENSIONS_ONLY" != true ] || [ "$CLI_INSTALL_POSTGIS" = true ]; }; then
        increment_step
        report_progress "Extensions Installation" $CURRENT_STEP 4 "Installing PostGIS"
        local postgis_installer
        if postgis_installer=$(find_postgis_installer "$INSTALL_FILES_DIR"); then
            distribute_postgis_installer "$postgis_installer" "${all_hosts[@]}"
            install_postgis_binaries "${all_hosts[@]}" "$postgis_installer"
            enable_postgis_extension "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
            verify_postgis_installation "$GPDB_COORDINATOR_HOST" "${DATABASE_NAME:-tdi}"
        else
            log_warn "PostGIS installer not found; skipping"
        fi
    else
        log_info "PostGIS installation skipped"
    fi

    # Spark Connector
    if should_install_spark_connector && { [ "$EXTENSIONS_ONLY" != true ] || [ "$CLI_INSTALL_SPARK_CONNECTOR" = true ]; }; then
        increment_step
        report_progress "Extensions Installation" $CURRENT_STEP 4 "Installing Spark Connector"
        local spark_tarball
        if spark_tarball=$(find_spark_connector_tarball "$INSTALL_FILES_DIR"); then
            distribute_spark_connector "$spark_tarball" "${all_hosts[@]}"
            install_spark_connector_binaries "${all_hosts[@]}" "$spark_tarball"
            setup_spark_connector_environment "${all_hosts[@]}"
            verify_spark_connector_installation "$GPDB_COORDINATOR_HOST"
        else
            log_warn "Spark Connector tarball not found; skipping"
        fi
    else
        log_info "Spark Connector installation skipped"
    fi

    report_phase_complete "Extensions Installation"
    touch "$STATE_DIR/.step_phase_extensions_installation"
}

# Phase 7: Completion
phase_completion() {
    if [ -f "$STATE_DIR/.step_phase_completion" ]; then
        log_info "Completion phase already completed, skipping."
        return
    fi
    report_phase_start 5 "Completion"
    
    increment_step
    report_progress "Completion" $CURRENT_STEP 1 "Final verification"
    
    # Test cluster connectivity and provide detailed status
    log_info "Performing final cluster verification..."
    
    # Check if cluster is running
    if ssh_execute "$GPDB_COORDINATOR_HOST" "sudo -u gpadmin bash -c 'source ~/.bashrc && gpstate -s'" "30" "true" 2>/dev/null; then
        log_success "✅ Cluster status check passed"
        
        # Test database connectivity
        if test_greenplum_connectivity "$GPDB_COORDINATOR_HOST"; then
            log_success_with_timestamp "🎉 Greenplum installation completed successfully!"
            echo ""
            log_info "=== Connection Information ==="
            log_info "Database Host: $GPDB_COORDINATOR_HOST"
            log_info "Database Name: tdi"
            log_info "Admin User: gpadmin"
            echo ""
            log_info "=== Quick Commands ==="
            log_info "Connect to database: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'psql -d tdi'"
            log_info "Check cluster status: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'gpstate -s'"
            log_info "Stop cluster: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'gpstop -a'"
            log_info "Start cluster: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'gpstart -a'"
            echo ""
            # Check if PXF was installed
            if [ -f "$STATE_DIR/.step_phase_pxf_installation" ]; then
                log_info "=== PXF (Platform Extension Framework) ==="
                log_info "PXF Status: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'pxf cluster status'"
                log_info "PXF Start: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'pxf cluster start'"
                log_info "PXF Stop: ssh $GPDB_COORDINATOR_HOST -l gpadmin 'pxf cluster stop'"
            fi
        else
            log_warn "⚠️ Cluster is running but connectivity test failed"
            log_info "The cluster may be initializing. Try connecting manually:"
            log_info "ssh $GPDB_COORDINATOR_HOST -l gpadmin 'psql -d tdi'"
        fi
    else
        log_warn "⚠️ Cluster status check failed"
        log_info "The cluster may not be running. Try starting it manually:"
        log_info "ssh $GPDB_COORDINATOR_HOST -l gpadmin 'gpstart -a'"
    fi
    
    report_phase_complete "Completion"
    touch "$STATE_DIR/.step_phase_completion"
}

# Function to collect user credentials
collect_credentials() {
    log_info "Collecting user credentials..."
    
    # Ask if SSH password is consistent across all hosts
    echo ""
    log_info "SSH Access Configuration:"
    echo "  Target hosts: $(get_all_hosts)"
    echo ""
    echo "💡 Password Reuse: The installer can store your root password securely in memory"
    echo "   and reuse it across all servers to avoid repeated prompts."
    echo ""
    read -p "Do all hosts use the same SSH password for root user? (y/n) [y]: " same_ssh_password
    same_ssh_password=${same_ssh_password:-y}
    
    if [[ "$same_ssh_password" =~ ^[Yy]$ ]]; then
        read -s -p "Enter SSH password for root user (will be reused for all hosts): " SSH_PASSWORD
        echo ""
        if [ -z "$SSH_PASSWORD" ]; then
            log_error "SSH password cannot be empty"
        fi
        export SSH_PASSWORD
        export SSHPASS="$SSH_PASSWORD"
        log_success "✅ SSH password stored securely - will be reused for all hosts"
        
        # Check/install sshpass for automated authentication
        if ! command -v sshpass >/dev/null 2>&1; then
            log_info "Installing sshpass for seamless password authentication..."
            # Try different package managers
            sshpass_installed=false
            if command -v yum >/dev/null 2>&1; then
                if sudo yum install -y sshpass 2>/dev/null; then
                    log_success "✅ sshpass installed via yum"
                    sshpass_installed=true
                fi
            elif command -v dnf >/dev/null 2>&1; then
                if sudo dnf install -y sshpass 2>/dev/null; then
                    log_success "✅ sshpass installed via dnf"
                    sshpass_installed=true
                fi
            elif command -v apt-get >/dev/null 2>&1; then
                if sudo apt-get update && sudo apt-get install -y sshpass 2>/dev/null; then
                    log_success "✅ sshpass installed via apt-get"
                    sshpass_installed=true
                fi
            elif command -v brew >/dev/null 2>&1; then
                log_info "Using Homebrew to install sshpass (this may take a moment)..."
                if brew install sshpass; then
                    log_success "✅ sshpass installed via Homebrew"
                    sshpass_installed=true
                else
                    log_warn "Homebrew install failed, trying alternative..."
                fi
            fi
            
            if [ "$sshpass_installed" = false ]; then
                log_warn "⚠️  Could not install sshpass automatically - you may be prompted for passwords occasionally"
                log_info "To install manually: sudo yum install sshpass (RHEL/CentOS) or sudo apt-get install sshpass (Ubuntu/Debian)"
            fi
        else
            log_success "✅ sshpass available - fully automated password authentication enabled"
        fi
    else
        log_warn "❌ Password reuse disabled - you'll be prompted for each connection"
        unset SSH_PASSWORD
        unset SSHPASS
    fi
    
    # Get sudo password
    echo ""
    read -s -p "Enter sudo password for all hosts: " SUDO_PASSWORD
    echo ""
    if [ -z "$SUDO_PASSWORD" ]; then
        log_error "Sudo password cannot be empty"
    fi
    
    # Get gpadmin password (use from config if available)
    if [ -z "$GPADMIN_PASSWORD" ]; then
        read -s -p "Enter password for gpadmin user: " GPADMIN_PASSWORD
        echo ""
        if [ -z "$GPADMIN_PASSWORD" ]; then
            log_error "Gpadmin password cannot be empty"
        fi
        
        # Validate password strength
        validate_password "$GPADMIN_PASSWORD" "gpadmin"
    else
        log_info "Using gpadmin password from configuration file"
    fi
    
    log_success "Credentials collected"
}

# Function to setup users and directories
setup_users_and_directories() {
    local hosts=("$@")
    
    log_info "Setting up users and directories..."
    
    for host in "${hosts[@]}"; do
        log_info "Setting up host: $host"
        create_gpadmin_user "$host"
    done
    
    log_success "Users and directories setup completed"
}

# Function to create gpadmin user on a host
create_gpadmin_user() {
    local host="$1"
    
    log_info "Creating gpadmin user on $host..."
    
    # Debug: show variables before creating remote script
    log_info "Debug: GPDB_DATA_ROOT='$GPDB_DATA_ROOT'"
    
    # Expand variables before creating remote script
    local data_root="$GPDB_DATA_ROOT"
    local gpadmin_password="$GPADMIN_PASSWORD"
    local sudo_password="$SUDO_PASSWORD"
    
    # Debug: show expanded variables
    log_info "Debug: data_root='$data_root'"
    
    # Validate required variables
    if [ -z "$data_root" ]; then
        log_error "GPDB_DATA_ROOT is not set or is empty"
        return 1
    fi
    
    local remote_script="
        set -e
        echo \"Debug: Creating data root directory '$data_root' and subdirectories\"
        if ! getent group gpadmin > /dev/null; then
            groupadd gpadmin
        fi
        
        if ! id -u gpadmin > /dev/null 2>&1; then
            useradd -g gpadmin -m -d /home/gpadmin gpadmin
        fi
        
        echo \"gpadmin:$gpadmin_password\" | chpasswd
        
        # Create data root and subdirectories
        mkdir -p \"/usr/local\" \"$data_root\" \"$data_root/coordinator\" \"$data_root/primary\" \"$data_root/mirror\"
        chown -R gpadmin:gpadmin \"/usr/local\" \"$data_root\"
        chmod 755 \"/usr/local\" \"$data_root\" \"$data_root/coordinator\" \"$data_root/primary\" \"$data_root/mirror\"
    "
    
    # Execute the remote script
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would execute user creation script on $host"
    else
        ssh_execute "$host" "echo '$sudo_password' | sudo -S bash -c \"$remote_script\""
    fi
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
    
    # Ensure configuration is loaded (safety check)
    if [ -z "$GPDB_COORDINATOR_HOST" ] || [ -z "$COORDINATOR_DATA_DIR" ]; then
        log_info "Reloading configuration..."
        load_configuration "$CONFIG_FILE"
    fi
    
    # Debug: Show variables before generating config
    log_info "Debug - Configuration variables:"
    log_info "  GPDB_COORDINATOR_HOST: '$GPDB_COORDINATOR_HOST'"
    log_info "  GPDB_SEGMENT_HOSTS: '${GPDB_SEGMENT_HOSTS[@]}'"
    log_info "  COORDINATOR_DATA_DIR: '$COORDINATOR_DATA_DIR'"
    log_info "  SEGMENT_DATA_DIR: '$SEGMENT_DATA_DIR'"
    log_info "  MIRROR_DATA_DIR: '$MIRROR_DATA_DIR'"
    
    # Generate configuration using library function
    log_info "Calling generate_gpinitsystem_config..."
    
    # Call function directly - no output capture at all
    generate_gpinitsystem_config "$GPDB_COORDINATOR_HOST" "${GPDB_SEGMENT_HOSTS[@]}"
    
    # Files should now exist
    local config_file="/tmp/gpinitsystem_config"
    local machine_list_file="/tmp/machine_list"
    
    # Verify files were created
    if [ ! -f "$config_file" ] || [ ! -f "$machine_list_file" ]; then
        log_error "Configuration files were not created"
        log_error "  Config file exists: $([ -f "$config_file" ] && echo "YES" || echo "NO")"
        log_error "  Machine list exists: $([ -f "$machine_list_file" ] && echo "YES" || echo "NO")"
        ls -la /tmp/gpinitsystem* /tmp/machine* 2>/dev/null || log_error "No temp files found"
        return 1
    fi
    
    log_success "Configuration files verified: $config_file"
    
    # Create data directories
    create_data_directories "${all_hosts[@]}"
    
    # Final verification before cluster initialization
    log_info "Final check before cluster initialization..."
    if [ ! -f "$config_file" ] || [ ! -f "$machine_list_file" ]; then
        log_error "Config files disappeared before cluster initialization!"
        log_error "Config file exists: $([ -f "$config_file" ] && echo YES || echo NO)"
        log_error "Machine list exists: $([ -f "$machine_list_file" ] && echo YES || echo NO)"
        ls -la /tmp/gp* /tmp/machine* 2>/dev/null || true
        return 1
    fi
    log_info "Config files still exist, proceeding with cluster initialization"
    
    # Initialize cluster
    initialize_greenplum_cluster "$GPDB_COORDINATOR_HOST" "$config_file" "$machine_list_file"
    
    # Setup environment
    setup_gpadmin_environment "${all_hosts[@]}"
    
    # Configure pg_hba.conf
    configure_pg_hba "$GPDB_COORDINATOR_HOST" "${all_hosts[@]}"
    
    # Restart cluster
    # restart_greenplum_cluster "$GPDB_COORDINATOR_HOST"
    
    log_success "Cluster initialization completed"
}

# Function to clean Greenplum and data directories
clean_greenplum() {
    local all_hosts=($(get_all_hosts))
    log_warn "CLEAN MODE: This will remove Greenplum and all data directories from all hosts!"
    for host in "${all_hosts[@]}"; do
        log_info "[CLEAN] Removing data root directory $GPDB_DATA_ROOT on $host..."
        execute_command "ssh_execute '$host' 'sudo rm -rf $GPDB_DATA_ROOT'"
        log_info "[CLEAN] Attempting to remove parent directory $(dirname $GPDB_DATA_ROOT) on $host (if empty)..."
        execute_command "ssh_execute '$host' 'sudo rmdir $(dirname $GPDB_DATA_ROOT) 2>/dev/null || true'"
        log_info "[CLEAN] Uninstalling Greenplum on $host..."
        execute_command "ssh_execute '$host' 'sudo yum remove -y greenplum-db-7'"
    done
    log_success "Greenplum and all data directories removed from all hosts."
}


# Note: gpinitsystem configuration generation and cluster initialization 
# functions are now handled by lib/greenplum.sh

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
    if [ "$EXTENSIONS_ONLY" = true ]; then
        phase_initialization
        phase_preflight_checks
        phase_extensions_installation
        phase_completion
    else
        phase_initialization
        phase_preflight_checks
        phase_host_setup
        phase_greenplum_installation
        phase_pxf_installation
        phase_extensions_installation
        phase_completion
    fi
    
    log_success_with_timestamp "Installation completed successfully!"
    
    # Leave temporary files in place for potential debugging or cleanup script to handle
}

# Execute main function with all arguments
main "$@"