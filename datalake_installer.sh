#!/bin/bash

# Tanzu Data Lake Controller 2.0 Installer
# Automated installation script for VMware Tanzu Data Lake Controller

# Global configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR="$SCRIPT_DIR/lib"
readonly CONFIG_FILE="datalake_config.conf"
readonly INSTALL_FILES_DIR="files"

# Global variables
DRY_RUN=false
NO_RPMS=false
PHASES=(
    "Initialization:2"
    "Pre-flight Checks:4"
    "Controller Installation:3"
    "Configuration:2"
    "Completion:1"
)

# State management variables
RESET_STATE=false
CLEAN_MODE=false

# Load required libraries
source "$LIB_DIR/error_handling.sh"
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/validation.sh"
source "$LIB_DIR/system.sh"
source "$LIB_DIR/ssh.sh"

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Tanzu Data Lake Controller 2.0 Installer - Automated setup for VMware TDL Controller

OPTIONS:
    --dry-run       Run in dry-run mode (no actual changes)
    --config FILE   Use specific configuration file
    --help          Show this help message
    --version       Show version information
    --force         Force a fresh install (clear state markers)
    --reset         Alias for --force
    --clean         Remove TDL Controller from host, then exit
    --no-rpms       Skip RPM operations (assumes RPM already on host)

EXAMPLES:
    $0                    # Run with default configuration
    $0 --dry-run          # Test run without making changes
    $0 --config custom.conf  # Use custom configuration file
    $0 --no-rpms          # Skip RPM operations (RPM already on host)
    $0 --clean            # Remove TDL Controller

REQUIREMENTS:
    - RHEL 8.x or 9.x family OS
    - Superuser/sudo privileges
    - TDL Controller RPM in files/ directory
    - Minimum: 1 vCPU, 512MB RAM, 5GB disk

EOF
}

# Function to show version
show_version() {
    echo "Tanzu Data Lake Controller 2.0 Installer v1.0"
    echo "Automated installation for VMware TDL Controller 2.0"
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
            --no-rpms)
                NO_RPMS=true
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

# Load and validate TDL Controller configuration
load_tdl_configuration() {
    local config_file="$1"
    
    log_info "Loading TDL Controller configuration from $config_file..."
    
    # Source the configuration file
    if [ -f "$config_file" ]; then
        source "$config_file"
    else
        log_error "Configuration file not found: $config_file"
    fi
    
    # Validate required variables
    local required_vars=(
        "TDL_CONTROLLER_HOST"
        "TDL_CONTROLLER_RPM"
        "TDL_ADMIN_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log_error "Required configuration variable '$var' is not set"
        fi
    done
    
    # Set defaults for optional variables
    TDL_CONTROLLER_PORT=${TDL_CONTROLLER_PORT:-8080}
    TDL_ADMIN_NAME=${TDL_ADMIN_NAME:-"Admin User"}
    TDL_ADMIN_EMAIL=${TDL_ADMIN_EMAIL:-"admin@example.com"}
    
    log_success "Configuration loaded successfully"
    
    # Display configuration summary
    log_info "=== TDL Controller Configuration ==="
    log_info "Controller Host: $TDL_CONTROLLER_HOST"
    log_info "Controller RPM: $TDL_CONTROLLER_RPM"
    log_info "Controller Port: $TDL_CONTROLLER_PORT"
    log_info "Admin Name: $TDL_ADMIN_NAME"
    log_info "Admin Email: $TDL_ADMIN_EMAIL"
}

# Configure TDL Controller installation (interactive setup)
configure_tdl_installation() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        log_info "Configuration file $config_file already exists."
        echo ""
        log_info "=== Current Configuration ==="
        # Display current config values (mask passwords)
        if [ -f "$config_file" ]; then
            source "$config_file"
            log_info "Controller Host: ${TDL_CONTROLLER_HOST:-'not set'}"
            log_info "Controller RPM: ${TDL_CONTROLLER_RPM:-'not set'}"
            log_info "Controller Port: ${TDL_CONTROLLER_PORT:-'not set'}"
            log_info "Admin Name: ${TDL_ADMIN_NAME:-'not set'}"
            log_info "Admin Email: ${TDL_ADMIN_EMAIL:-'not set'}"
            log_info "Admin Password: ${TDL_ADMIN_PASSWORD:+[configured]}"
        fi
        echo ""
        read -p "Do you want to reconfigure? (y/n) [n]: " reconfigure
        reconfigure=${reconfigure:-n}
        if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    if [ ! -f "$config_file" ] && [ -f "${config_file}.template" ]; then
        log_info "Creating configuration file from template..."
        cp "${config_file}.template" "$config_file"
        log_success "Configuration file created: $config_file"
    fi
    
    log_info "=== TDL Controller Configuration Setup ==="
    echo ""
    
    # Get controller host
    read -p "Enter controller host (where TDL Controller will be installed) [localhost]: " controller_host
    controller_host=${controller_host:-localhost}
    
    # Get SSH credentials first for OS detection
    echo ""
    read -s -p "Enter SSH password for root@$controller_host: " temp_ssh_password
    echo ""
    if [ -z "$temp_ssh_password" ]; then
        log_error "SSH password cannot be empty"
        return 1
    fi
    export SSHPASS="$temp_ssh_password"
    
    # Detect OS version for RPM selection
    echo ""
    log_info "Detecting OS version for RPM selection..."
    local os_version=""
    local detected_version=$(sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$controller_host" "cat /etc/os-release | grep VERSION_ID | cut -d'=' -f2 | tr -d '\"' | cut -d'.' -f1" 2>/dev/null)
    local detected_os=$(sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$controller_host" "cat /etc/os-release | grep '^ID=' | cut -d'=' -f2 | tr -d '\"'" 2>/dev/null)
    
    if [[ "$detected_version" == "8" ]]; then
        os_version="el8"
        log_info "Detected $detected_os $detected_version (RHEL 8 family) - will use el8 RPM"
    elif [[ "$detected_version" == "9" ]]; then
        os_version="el9"
        log_info "Detected $detected_os $detected_version (RHEL 9 family) - will use el9 RPM"
    else
        log_warn "Could not detect OS version (found: $detected_os $detected_version). Please specify manually."
        read -p "Enter OS version (el8 or el9): " os_version
    fi
    
    # Suggest RPM filename
    local suggested_rpm="tdl-controller-2.0.${os_version}.x86_64.rpm"
    read -p "Enter TDL Controller RPM filename [$suggested_rpm]: " controller_rpm
    controller_rpm=${controller_rpm:-$suggested_rpm}
    
    # Get controller port
    read -p "Enter controller web UI port [8080]: " controller_port
    controller_port=${controller_port:-8080}
    
    # Get admin user details
    echo ""
    log_info "Configure initial admin user:"
    read -p "Admin user full name [Admin User]: " admin_name
    admin_name=${admin_name:-"Admin User"}
    
    read -p "Admin email [admin@example.com]: " admin_email
    admin_email=${admin_email:-"admin@example.com"}
    
    read -s -p "Admin password: " admin_password
    echo ""
    if [ -z "$admin_password" ]; then
        log_error "Admin password cannot be empty"
    fi
    
    # Create/update configuration file
    log_info "Updating configuration file..."
    
    cat > "$config_file" << EOF
# Tanzu Data Lake Controller 2.0 Installation Configuration
# Generated by datalake_installer.sh

# Controller host (where TDL Controller 2.0 will be installed)
TDL_CONTROLLER_HOST="$controller_host"

# TDL Controller package file (place in files/ directory)
TDL_CONTROLLER_RPM="$controller_rpm"

# Controller web UI port (default 8080)
TDL_CONTROLLER_PORT=$controller_port

# Initial admin user configuration
TDL_ADMIN_NAME="$admin_name"
TDL_ADMIN_EMAIL="$admin_email"
TDL_ADMIN_PASSWORD="$admin_password"
EOF
    
    log_success "Configuration file updated: $config_file"
    log_warn "Remember to secure this file as it contains passwords!"
}

# Phase 1: Initialization
phase_initialization() {
    if [ -f "$STATE_DIR/.step_phase_initialization" ]; then
        log_info "Initialization phase already completed, skipping."
        load_tdl_configuration "$CONFIG_FILE"
        return
    fi
    report_phase_start 1 "Initialization"
    
    increment_step
    report_progress "Initialization" $CURRENT_STEP 2 "Setting up environment"
    
    # Setup signal handlers
    setup_signal_handlers
    
    # Create install files directory
    mkdir -p "$INSTALL_FILES_DIR"
    log_info "Install files directory: $INSTALL_FILES_DIR"
    
    increment_step
    report_progress "Initialization" $CURRENT_STEP 2 "Loading configuration"
    
    # Configure installation
    configure_tdl_installation "$CONFIG_FILE"
    
    # Load and validate configuration
    load_tdl_configuration "$CONFIG_FILE"
    
    report_phase_complete "Initialization"
    touch "$STATE_DIR/.step_phase_initialization"
}

# Phase 2: Pre-flight Checks
phase_preflight_checks() {
    if [ -f "$STATE_DIR/.step_phase_preflight" ]; then
        log_info "Pre-flight Checks phase already completed, skipping."
        load_tdl_configuration "$CONFIG_FILE" 2>/dev/null || true
        return
    fi
    report_phase_start 2 "Pre-flight Checks"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 4 "Collecting credentials"
    collect_tdl_credentials
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 4 "Establishing SSH connection"
    cleanup_all_ssh_connections
    establish_ssh_connections "root@$TDL_CONTROLLER_HOST"
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 4 "Checking OS compatibility"
    check_tdl_os_compatibility
    
    increment_step
    report_progress "Pre-flight Checks" $CURRENT_STEP 4 "Verifying RPM package"
    verify_tdl_rpm_package_local
    
    report_phase_complete "Pre-flight Checks"
    touch "$STATE_DIR/.step_phase_preflight"
}

# Collect TDL Controller credentials
collect_tdl_credentials() {
    log_info "Collecting credentials for TDL Controller installation..."
    
    echo ""
    log_info "SSH Access Configuration:"
    echo "  Target host: root@$TDL_CONTROLLER_HOST"
    echo ""
    
    read -s -p "Enter SSH password for root@$TDL_CONTROLLER_HOST: " SSH_PASSWORD
    echo ""
    if [ -z "$SSH_PASSWORD" ]; then
        log_error "SSH password cannot be empty"
    fi
    export SSH_PASSWORD
    export SSHPASS="$SSH_PASSWORD"
    
    # No sudo password needed since we're using root
    log_info "Using root access - no sudo password needed"
    
    log_success "Credentials collected"
}

# Check TDL Controller OS compatibility locally
check_tdl_os_compatibility_local() {
    log_info "Checking OS compatibility locally..."
    
    # Get local OS information
    local os_release=$(cat /etc/os-release 2>/dev/null | grep -E '^ID=' | cut -d'=' -f2 | tr -d '"' || echo "unknown")
    local os_version=$(cat /etc/os-release 2>/dev/null | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1 || echo "unknown")
    
    # Debug output
    log_info "Detected OS ID: '$os_release'"
    log_info "Detected OS Version: '$os_version'"
    
    # Supported: RHEL, CentOS, Rocky Linux, Oracle Linux (RHEL 8.x/9.x families)
    if [[ "$os_release" =~ ^(rhel|centos|rocky|ol|almalinux)$ ]]; then
        if [[ "$os_version" =~ ^(8|9)$ ]]; then
            log_success "OS $os_release $os_version is compatible (RHEL $os_version family)"
        else
            log_error "Incompatible OS version: $os_release $os_version. Only RHEL 8.x or 9.x families are supported."
        fi
    else
        log_error "Unsupported OS: '$os_release'. Supported: RHEL, CentOS, Rocky Linux, Oracle Linux, AlmaLinux (8.x/9.x families)"
    fi
}

# Check TDL Controller OS compatibility
check_tdl_os_compatibility() {
    log_info "Checking OS compatibility on $TDL_CONTROLLER_HOST..."
    
    # Use silent mode to avoid SSH warnings interfering with output
    local os_release=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "cat /etc/os-release | grep -E '^ID=' | cut -d'=' -f2 | tr -d '\"'" "" "true")
    local os_version=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "cat /etc/os-release | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '\"' | cut -d'.' -f1" "" "true")
    
    # Debug output
    log_info "Detected OS ID: '$os_release'"
    log_info "Detected OS Version: '$os_version'"
    
    # Supported: RHEL, CentOS, Rocky Linux, Oracle Linux (RHEL 8.x/9.x families)
    if [[ "$os_release" =~ ^(rhel|centos|rocky|ol|almalinux)$ ]]; then
        if [[ "$os_version" =~ ^(8|9)$ ]]; then
            log_success "OS $os_release $os_version is compatible (RHEL $os_version family)"
        else
            log_error "Incompatible OS version: $os_release $os_version. Only RHEL 8.x or 9.x families are supported."
        fi
    else
        log_error "Unsupported OS: '$os_release'. Supported: RHEL, CentOS, Rocky Linux, Oracle Linux, AlmaLinux (8.x/9.x families)"
    fi
}

# Check TDL Controller system resources
check_tdl_system_resources() {
    log_info "Checking system resources on $TDL_CONTROLLER_HOST..."
    
    # Check RAM (minimum 512MB) - use silent mode
    local ram_mb=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "free -m | awk '/^Mem:/{print \$2}'" "" "true")
    if [ "$ram_mb" -lt 512 ]; then
        log_error "Insufficient RAM: ${ram_mb}MB (minimum: 512MB)"
    else
        log_success "RAM check passed: ${ram_mb}MB"
    fi
    
    # Check CPU cores (minimum 1) - use silent mode
    local cores=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "nproc" "" "true")
    if [ "$cores" -lt 1 ]; then
        log_error "Insufficient CPU cores: $cores (minimum: 1)"
    else
        log_success "CPU check passed: $cores cores"
    fi
    
    # Check disk space (minimum 5GB) - use silent mode
    local disk_gb=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "df -BG /opt | tail -1 | awk '{print \$4}' | sed 's/G//'" "" "true")
    if [ "$disk_gb" -lt 5 ]; then
        log_error "Insufficient disk space: ${disk_gb}GB (minimum: 5GB)"
    else
        log_success "Disk space check passed: ${disk_gb}GB available"
    fi
}

# Verify TDL Controller RPM package
verify_tdl_rpm_package() {
    log_info "Verifying TDL Controller RPM package..."
    
    local rpm_path="$INSTALL_FILES_DIR/$TDL_CONTROLLER_RPM"
    
    if [ ! -f "$rpm_path" ]; then
        log_error "TDL Controller RPM not found: $rpm_path"
        log_info "Please download the RPM from Broadcom Support Portal and place it in the files/ directory"
        return 1
    fi
    
    # Basic file existence and size check
    local file_size=$(stat -f%z "$rpm_path" 2>/dev/null || stat -c%s "$rpm_path" 2>/dev/null)
    if [ "$file_size" -lt 1000 ]; then
        log_error "RPM file appears too small: $file_size bytes"
        return 1
    fi
    
    log_success "RPM package found: $rpm_path (${file_size} bytes)"
    
    # Check filename format
    if [[ "$TDL_CONTROLLER_RPM" =~ ^tdl-controller-.*\.(el8|el9)\.x86_64\.rpm$ ]]; then
        log_success "RPM filename format is correct"
    else
        log_warn "RPM filename format may not match expected pattern: tdl-controller-*.el[8|9].x86_64.rpm"
    fi
    
    # Verify architecture from filename
    if [[ "$TDL_CONTROLLER_RPM" == *".x86_64.rpm" ]]; then
        log_success "Architecture check passed: x86_64"
    else
        log_warn "RPM architecture may not match requirements (expected x86_64)"
    fi
    
    # Note: RPM content validation will be done on the target host during installation
    log_info "RPM content will be validated on target host during installation"
}

# Verify TDL Controller RPM package locally
verify_tdl_rpm_package_local() {
    log_info "Verifying TDL Controller RPM package locally..."
    
    local rpm_path="$INSTALL_FILES_DIR/$TDL_CONTROLLER_RPM"
    
    if [ ! -f "$rpm_path" ]; then
        log_error "TDL Controller RPM not found: $rpm_path"
        log_info "Expected RPM should be deployed via push_to_server.sh"
        return 1
    fi
    
    # Basic file existence and size check
    local file_size=$(stat -f%z "$rpm_path" 2>/dev/null || stat -c%s "$rpm_path" 2>/dev/null)
    if [ "$file_size" -lt 1000 ]; then
        log_error "RPM file appears too small: $file_size bytes"
        return 1
    fi
    
    log_success "RPM package found locally: $rpm_path (${file_size} bytes)"
    
    # Check filename format
    if [[ "$TDL_CONTROLLER_RPM" =~ ^tdl-controller-.*\.(el8|el9)\.x86_64\.rpm$ ]]; then
        log_success "RPM filename format is correct"
    else
        log_warn "RPM filename format may not match expected pattern: tdl-controller-*.el[8|9].x86_64.rpm"
    fi
    
    log_success "Local RPM package verification completed"
}

# Copy RPM to target host
copy_rpm_to_host() {
    log_info "Copying RPM package to $TDL_CONTROLLER_HOST..."
    
    local rpm_path="$INSTALL_FILES_DIR/$TDL_CONTROLLER_RPM"
    local remote_path="/tmp/$TDL_CONTROLLER_RPM"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would copy $rpm_path to $TDL_CONTROLLER_HOST:$remote_path"
    else
        scp "$rpm_path" "root@$TDL_CONTROLLER_HOST:$remote_path"
        log_success "RPM package copied to target host"
    fi
}

# Install TDL Controller RPM on remote host
install_tdl_controller_remote() {
    log_info "Installing TDL Controller RPM on $TDL_CONTROLLER_HOST..."
    
    local remote_path="/tmp/$TDL_CONTROLLER_RPM"
    
    # Use the same pattern as GPDB installer
    local remote_script="
        set -e
        echo \"Installing TDL Controller RPM...\"
        if rpm -q tdl-controller 2>/dev/null; then
            echo \"TDL Controller is already installed.\"
        else
            yum install -y $remote_path
        fi
        
        echo \"Enabling tdl-controller service...\"
        systemctl enable tdl-controller
        
        echo \"Cleaning up temporary RPM...\"
        rm -f $remote_path
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would install TDL Controller RPM on $TDL_CONTROLLER_HOST"
    else
        log_info "Executing remote installation..."
        if ssh_execute "root@$TDL_CONTROLLER_HOST" "$remote_script"; then
            log_success "TDL Controller RPM installed successfully on $TDL_CONTROLLER_HOST"
        else
            log_error "Failed to install TDL Controller RPM on $TDL_CONTROLLER_HOST"
            return 1
        fi
    fi
}

# Phase 3: Controller Installation
phase_controller_installation() {
    if [ -f "$STATE_DIR/.step_phase_installation" ]; then
        log_info "Controller Installation phase already completed, skipping."
        return
    fi
    report_phase_start 3 "Controller Installation"
    
    increment_step
    report_progress "Controller Installation" $CURRENT_STEP 3 "Copying RPM to target host"
    copy_rpm_to_host
    
    increment_step
    report_progress "Controller Installation" $CURRENT_STEP 3 "Installing TDL Controller on target host"
    install_tdl_controller_remote
    
    increment_step
    report_progress "Controller Installation" $CURRENT_STEP 3 "Starting controller service"
    start_tdl_controller_service
    
    report_phase_complete "Controller Installation"
    touch "$STATE_DIR/.step_phase_installation"
}

# Copy RPM to host
copy_rpm_to_host() {
    log_info "Copying RPM package to $TDL_CONTROLLER_HOST..."
    
    local rpm_path="$INSTALL_FILES_DIR/$TDL_CONTROLLER_RPM"
    local remote_path="/tmp/$TDL_CONTROLLER_RPM"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would copy $rpm_path to $TDL_CONTROLLER_HOST:$remote_path"
    else
        scp "$rpm_path" "root@$TDL_CONTROLLER_HOST:$remote_path"
        log_success "RPM package copied to host"
    fi
}

# Validate RPM on target host
validate_rpm_on_host() {
    log_info "Validating RPM package on target host..."
    
    local remote_path="/tmp/$TDL_CONTROLLER_RPM"
    
    local validation_script="
        set -e
        echo \"Validating RPM package: $remote_path\"
        
        # Check if file exists and is readable
        if [ ! -f \"$remote_path\" ]; then
            echo \"ERROR: RPM file not found: $remote_path\"
            exit 1
        fi
        
        # Validate RPM package integrity
        rpm -qp \"$remote_path\" --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\\n'
        
        # Check package signature (if applicable)
        rpm -Kv \"$remote_path\" || echo \"Warning: Package signature check failed or not signed\"
        
        echo \"RPM validation completed successfully\"
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would validate RPM package on target host"
    else
        local rpm_info=$(ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$validation_script\"" "" "true")
        if [ $? -eq 0 ]; then
            log_success "RPM package validation passed on target host"
            log_info "Package info: $(echo "$rpm_info" | grep "tdl-controller" | head -1)"
        else
            log_error "RPM package validation failed on target host"
            return 1
        fi
    fi
}

# Install TDL Controller RPM
install_tdl_controller_rpm() {
    log_info "Installing TDL Controller RPM on $TDL_CONTROLLER_HOST..."
    
    local remote_path="/tmp/$TDL_CONTROLLER_RPM"
    
    local install_script="
        set -ex
        echo \"Installing TDL Controller RPM...\"
        if ! yum install -y $remote_path; then
            echo \"ERROR: Failed to install TDL Controller RPM\"
            exit 1
        fi
        
        echo \"Enabling tdl-controller service...\"
        if ! systemctl enable tdl-controller; then
            echo \"ERROR: Failed to enable tdl-controller service\"
            exit 1
        fi
        
        # Verify installation
        echo \"Verifying TDL Controller installation...\"
        if ! rpm -q tdl-controller; then
            echo \"ERROR: TDL Controller package not found after installation\"
            exit 1
        fi
        
        echo \"Cleaning up temporary RPM...\"
        rm -f $remote_path
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would install TDL Controller RPM"
    else
        ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$install_script\""
        log_success "TDL Controller RPM installed successfully"
    fi
}

# Install TDL Controller RPM (no-rpms mode)
install_tdl_controller_rpm_no_rpms() {
    log_info "Installing TDL Controller RPM on $TDL_CONTROLLER_HOST (--no-rpms mode)..."
    
    # In no-rpms mode, we look for RPM in multiple possible locations
    local search_paths=(
        "/home/gpadmin/gpdb_installer/files"
        "/root/gpdb_installer/files"
        "/opt/gpdb_installer/files"
        "/home/gpadmin/files"
        "/tmp" 
        "/root"
        "/opt"
        "."
    )
    
    local install_script="
        set -ex
        echo \"Searching for TDL Controller RPM in common locations...\"
        
        rpm_file=\"\"
        
        # Search in multiple locations
        for search_path in ${search_paths[@]}; do
            echo \"Searching in \$search_path...\"
            if [ -d \"\$search_path\" ]; then
                found_rpm=\$(find \"\$search_path\" -maxdepth 2 -name 'tdl-controller-*.rpm' -type f 2>/dev/null | head -1)
                if [ -n \"\$found_rpm\" ]; then
                    rpm_file=\"\$found_rpm\"
                    echo \"Found TDL Controller RPM: \$rpm_file\"
                    break
                fi
            fi
        done
        
        # If not found in common locations, do a broader search
        if [ -z \"\$rpm_file\" ]; then
            echo \"Doing broader search for TDL Controller RPM...\"
            rpm_file=\$(find / -name 'tdl-controller-*.rpm' -type f 2>/dev/null | head -1)
        fi
        
        if [ -z \"\$rpm_file\" ]; then
            echo \"ERROR: No TDL Controller RPM found on system\"
            echo \"Searched locations: ${search_paths[*]}\"
            echo \"Please ensure TDL Controller RPM is available on the target host\"
            exit 1
        fi
        
        echo \"Using TDL Controller RPM: \$rpm_file\"
        
        # Validate RPM before installation
        echo \"Validating RPM package...\"
        rpm -qp \"\$rpm_file\" --queryformat '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\\n'
        
        # Install the RPM
        echo \"Installing TDL Controller RPM...\"
        if ! yum install -y \"\$rpm_file\"; then
            echo \"ERROR: Failed to install TDL Controller RPM\"
            exit 1
        fi
        
        echo \"Enabling tdl-controller service...\"
        if ! systemctl enable tdl-controller; then
            echo \"ERROR: Failed to enable tdl-controller service\"
            exit 1
        fi
        
        # Verify installation
        echo \"Verifying TDL Controller installation...\"
        if ! rpm -q tdl-controller; then
            echo \"ERROR: TDL Controller package not found after installation\"
            exit 1
        fi
        
        echo \"TDL Controller installation completed successfully\"
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would search for and install TDL Controller RPM on target host"
    else
        log_info "Executing installation script on remote host..."
        if ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$install_script\"" "" "false"; then
            log_success "TDL Controller RPM found and installed successfully"
        else
            log_error "Failed to find or install TDL Controller RPM on target host"
            log_info "Please ensure the TDL Controller RPM is available in one of these locations:"
            for path in "${search_paths[@]}"; do
                log_info "  - $path"
            done
            return 1
        fi
    fi
}

# Start TDL Controller service
start_tdl_controller_service() {
    log_info "Starting TDL Controller service..."
    
    local service_script="
        set -e
        echo \"Starting tdl-controller service...\"
        systemctl start tdl-controller
        
        echo \"Checking service status...\"
        systemctl status tdl-controller --no-pager
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would start TDL Controller service"
    else
        ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$service_script\"" "" "60" "true"
        log_success "TDL Controller service started"
    fi
}

# Phase 4: Configuration
phase_configuration() {
    if [ -f "$STATE_DIR/.step_phase_configuration" ]; then
        log_info "Configuration phase already completed, skipping."
        return
    fi
    report_phase_start 4 "Configuration"
    
    increment_step
    report_progress "Configuration" $CURRENT_STEP 2 "Configuring firewall"
    configure_tdl_firewall
    
    increment_step
    report_progress "Configuration" $CURRENT_STEP 2 "Verifying web UI access"
    verify_web_ui_access
    
    report_phase_complete "Configuration"
    touch "$STATE_DIR/.step_phase_configuration"
}

# Configure TDL Controller firewall
configure_tdl_firewall() {
    log_info "Configuring firewall on $TDL_CONTROLLER_HOST..."
    
    local firewall_script="
        set -e
        echo \"Opening port $TDL_CONTROLLER_PORT for TDL Controller...\"
        firewall-cmd --permanent --add-port=$TDL_CONTROLLER_PORT/tcp
        firewall-cmd --reload
        
        echo \"Verifying firewall rules...\"
        firewall-cmd --list-ports | grep $TDL_CONTROLLER_PORT
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would configure firewall for port $TDL_CONTROLLER_PORT"
    else
        ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$firewall_script\"" "" "30" "true"
        log_success "Firewall configured for TDL Controller"
    fi
}

# Verify web UI access
verify_web_ui_access() {
    log_info "Verifying TDL Controller web UI access..."
    
    local web_url="https://$TDL_CONTROLLER_HOST:$TDL_CONTROLLER_PORT"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would verify web UI access at $web_url"
    else
        # Test if the port is listening
        if ssh_execute "root@$TDL_CONTROLLER_HOST" "netstat -tlnp | grep :$TDL_CONTROLLER_PORT" "" "10" "true"; then
            log_success "TDL Controller is listening on port $TDL_CONTROLLER_PORT"
        else
            log_warn "TDL Controller may not be fully started yet"
        fi
    fi
}

# Phase 5: Completion
phase_completion() {
    if [ -f "$STATE_DIR/.step_phase_completion" ]; then
        log_info "Completion phase already completed, skipping."
        return
    fi
    report_phase_start 5 "Completion"
    
    increment_step
    report_progress "Completion" $CURRENT_STEP 1 "Final verification and summary"
    
    log_success_with_timestamp "🎉 TDL Controller 2.0 installation completed!"
    echo ""
    log_info "=== Installation Summary ==="
    log_info "Controller Host: $TDL_CONTROLLER_HOST"
    log_info "Controller Port: $TDL_CONTROLLER_PORT"
    log_info "Web UI URL: https://$TDL_CONTROLLER_HOST:$TDL_CONTROLLER_PORT"
    echo ""
    log_info "=== Next Steps ==="
    log_info "1. Access the web UI: https://$TDL_CONTROLLER_HOST:$TDL_CONTROLLER_PORT"
    log_info "2. Register the first admin user:"
    log_info "   - Name: $TDL_ADMIN_NAME"
    log_info "   - Email: $TDL_ADMIN_EMAIL"
    log_info "   - Password: (configured in setup)"
    log_info "3. Add additional users and configure roles as needed"
    log_info "4. Upload certificates and configure Kerberos if required"
    echo ""
    log_info "=== Service Management ==="
    log_info "Start service:  ssh $TDL_CONTROLLER_HOST 'sudo systemctl start tdl-controller'"
    log_info "Stop service:   ssh $TDL_CONTROLLER_HOST 'sudo systemctl stop tdl-controller'"
    log_info "Check status:   ssh $TDL_CONTROLLER_HOST 'sudo systemctl status tdl-controller'"
    log_info "View logs:      ssh $TDL_CONTROLLER_HOST 'sudo journalctl -u tdl-controller -f'"
    
    report_phase_complete "Completion"
    touch "$STATE_DIR/.step_phase_completion"
}

# Function to clean TDL Controller installation
clean_tdl_controller() {
    log_warn "CLEAN MODE: This will remove TDL Controller from $TDL_CONTROLLER_HOST!"
    
    local clean_script="
        set -e
        echo \"Stopping TDL Controller service...\"
        systemctl stop tdl-controller || true
        systemctl disable tdl-controller || true
        
        echo \"Removing TDL Controller RPM...\"
        rpm -e tdl-controller || true
        
        echo \"Removing firewall rules...\"
        firewall-cmd --permanent --remove-port=$TDL_CONTROLLER_PORT/tcp || true
        firewall-cmd --reload || true
        
        echo \"TDL Controller removal completed.\"
    "
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY-RUN] Would remove TDL Controller from $TDL_CONTROLLER_HOST"
    else
        ssh_execute "root@$TDL_CONTROLLER_HOST" "bash -c \"$clean_script\""
        log_success "TDL Controller removed from $TDL_CONTROLLER_HOST"
    fi
}

# Main execution function
main() {
    echo -e "${COLOR_GREEN}Tanzu Data Lake Controller 2.0 Installer${COLOR_RESET}"
    log_info_with_timestamp "Starting TDL Controller installation process"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    STATE_DIR="/tmp/tdl_controller_installer_state"
    mkdir -p "$STATE_DIR"
    
    if [ "$CLEAN_MODE" = true ]; then
        # Need to load config for clean mode
        if [ -f "$CONFIG_FILE" ]; then
            load_tdl_configuration "$CONFIG_FILE"
            collect_tdl_credentials
            clean_tdl_controller
        else
            log_error "Configuration file required for clean mode: $CONFIG_FILE"
        fi
        exit 0
    fi
    
    if [ "$RESET_STATE" = true ]; then
        echo "[INFO] Clearing all step markers in $STATE_DIR..."
        rm -f $STATE_DIR/.step_*
    fi
    
    # Execute installation phases
    phase_initialization
    phase_preflight_checks
    phase_controller_installation
    phase_configuration
    phase_completion
    
    log_success_with_timestamp "TDL Controller installation completed successfully!"
}

# Execute main function with all arguments
main "$@"