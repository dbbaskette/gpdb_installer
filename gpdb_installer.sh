#!/bin/bash

# Tanzu Data Intelligence Installer Script
# Installs Greenplum Database v7 on one or more servers.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
CONFIG_FILE="gpdb_config.conf"
INSTALL_FILES_DIR="files"

DRY_RUN=false

# --- Colors for beautiful output ---
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'

# --- Helper Functions for logging ---
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
    exit 1
}

# --- Function to execute commands, respecting dry run ---
execute_command() {
    if $DRY_RUN; then
        log_info "[DRY-RUN] Would execute: $@"
    else
        "$@"
    fi
}

# --- Function to check if current user has sudo privileges ---
check_sudo_privileges() {
    log_info "Checking sudo privileges..."
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges. Please run as a user with sudo access."
    fi
    log_success "Sudo privileges confirmed."
}

# --- Function to check system resources ---
check_system_resources() {
    log_info "Checking system resources..."
    
    # Memory check (minimum 8GB, recommended 16GB)
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $2/1024}')
    if [ "$total_memory" -lt 8 ]; then
        log_error "Insufficient memory: ${total_memory}GB available, minimum 8GB required"
    elif [ "$total_memory" -lt 16 ]; then
        log_warn "Low memory: ${total_memory}GB available, 16GB recommended for production"
    else
        log_success "Memory check passed: ${total_memory}GB available"
    fi
    
    # Disk space check (minimum 10GB free)
    local free_space=$(df -BG "$GPDB_DATA_DIR" 2>/dev/null | awk 'NR==2{print $4}' | sed 's/G//' || echo "0")
    if [ "$free_space" -lt 10 ]; then
        log_error "Insufficient disk space: ${free_space}GB free, minimum 10GB required"
    else
        log_success "Disk space check passed: ${free_space}GB free"
    fi
}

# --- Function to check Greenplum version compatibility ---
check_greenplum_compatibility() {
    log_info "Checking Greenplum version compatibility..."
    
    local installer_file=$(find "$INSTALL_FILES_DIR" -maxdepth 1 -type f -name "greenplum-db-*.el*.x86_64.rpm" 2>/dev/null | head -n1)
    
    if [ -n "$installer_file" ]; then
        local gp_version=$(basename "$installer_file" | sed -n 's/greenplum-db-\([0-9]\+\.[0-9]\+\).*/\1/p')
        local os_version=$(cat /etc/os-release 2>/dev/null | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1 || echo "unknown")
        
        log_info "Detected Greenplum version: $gp_version"
        log_info "Detected OS version: $os_version"
        
        # Version compatibility checks
        case "$gp_version" in
            "7.0"|"7.1"|"7.2")
                if [[ "$os_version" =~ ^(7|8|9)$ ]]; then
                    log_success "Greenplum $gp_version is compatible with OS version $os_version"
                else
                    log_error "Greenplum $gp_version requires RHEL/CentOS/Rocky Linux 7, 8, or 9"
                fi
                ;;
            *)
                log_warn "Unknown Greenplum version $gp_version - compatibility not verified"
                ;;
        esac
    else
        log_warn "No Greenplum installer found - version compatibility not checked"
    fi
}

# --- Function to check library versions ---
check_library_versions() {
    log_info "Checking required library versions..."
    
    # Check for required libraries
    local required_libs=("libc.so.6" "libssl.so.1.1" "libcrypto.so.1.1")
    
    for lib in "${required_libs[@]}"; do
        if ldconfig -p 2>/dev/null | grep -q "$lib"; then
            log_success "Library $lib found"
        else
            log_warn "Library $lib not found - may cause installation issues"
        fi
    done
    
    # Check kernel parameters
    local kernel_params=("vm.overcommit_memory" "vm.swappiness" "kernel.shmmax")
    for param in "${kernel_params[@]}"; do
        local value=$(sysctl -n "$param" 2>/dev/null || echo "not_set")
        log_info "Kernel parameter $param: $value"
    done
}

# --- Function to check network connectivity ---
check_network_connectivity() {
    log_info "Checking network connectivity between hosts..."
    
    local all_hosts=($(get_all_hosts))
    
    for host in "${all_hosts[@]}"; do
        # Test basic connectivity
        if ping -c 3 "$host" >/dev/null 2>&1; then
            log_success "Host $host is reachable"
        else
            log_error "Host $host is not reachable"
        fi
        
        # Test SSH connectivity (if not localhost)
        if [[ "$host" != "$(hostname -s)" ]]; then
            if ssh -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo 'SSH test'" >/dev/null 2>&1; then
                log_success "SSH to $host works"
            else
                log_warn "SSH to $host may have issues"
            fi
        else
            log_info "Skipping SSH test for localhost"
        fi
    done
}

# --- Function to validate configuration ---
validate_configuration() {
    log_info "Validating configuration..."
    
    if [ -z "$GPDB_COORDINATOR_HOST" ]; then
        log_error "Coordinator host is not set in configuration."
    fi
    
    if [ ${#GPDB_SEGMENT_HOSTS[@]} -eq 0 ]; then
        log_error "No segment hosts defined in configuration."
    fi
    
    if [ -z "$GPDB_INSTALL_DIR" ]; then
        log_error "Install directory is not set in configuration."
    fi
    
    if [ -z "$GPDB_DATA_DIR" ]; then
        log_error "Data directory is not set in configuration."
    fi
    
    log_success "Configuration validation passed."
}

# --- Configuration Stage ---
# Prompts the user for installation details and saves them to a config file.
configure_installation() {
    log_info "Starting configuration..."
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Configuration file '$CONFIG_FILE' found."
        read -p "Do you want to use the existing configuration? (y/n) [y]: " use_existing
        use_existing=${use_existing:-y}
        if [[ "$use_existing" == "y" || "$use_existing" == "Y" ]]; then
            log_success "Using existing configuration."
            return
        fi
    fi

    log_info "No configuration found or re-configuration requested. Let's set it up."

    # Using `hostname -s` provides a sensible default for single-node installs
    read -p "Enter the coordinator hostname [$(hostname -s)]: " GPDB_COORDINATOR_HOST
    GPDB_COORDINATOR_HOST=${GPDB_COORDINATOR_HOST:-$(hostname -s)}

    read -p "Enter all segment hostnames (comma-separated, e.g., sdw1,sdw2): " GPDB_SEGMENT_HOSTS
    if [ -z "$GPDB_SEGMENT_HOSTS" ]; then
        log_info "No segment hosts entered. Assuming single-node installation on coordinator."
        GPDB_SEGMENT_HOSTS=$GPDB_COORDINATOR_HOST
    fi

    read -p "Do you want to set up a standby coordinator? (y/n) [n]: " setup_standby
    setup_standby=${setup_standby:-n}
    GPDB_STANDBY_HOST=""
    if [[ "$setup_standby" == "y" || "$setup_standby" == "Y" ]]; then
        read -p "Enter the standby coordinator hostname: " GPDB_STANDBY_HOST
        if [ -z "$GPDB_STANDBY_HOST" ]; then
            log_error "Standby coordinator hostname cannot be empty."
        fi
    fi

    read -p "Enter the Greenplum installation directory [/usr/local/greenplum-db]: " GPDB_INSTALL_DIR
    GPDB_INSTALL_DIR=${GPDB_INSTALL_DIR:-/usr/local/greenplum-db}

    read -p "Enter the primary data directory for segments [/data/primary]: " GPDB_DATA_DIR
    GPDB_DATA_DIR=${GPDB_DATA_DIR:-/data/primary}

    # Create the configuration file
    cat > "$CONFIG_FILE" << EOL
# Greenplum Database Installation Configuration
# This file is auto-generated by the installer script.

GPDB_COORDINATOR_HOST="$GPDB_COORDINATOR_HOST"
GPDB_STANDBY_HOST="$GPDB_STANDBY_HOST"
GPDB_SEGMENT_HOSTS=($(echo "$GPDB_SEGMENT_HOSTS" | tr ',' ' '))
GPDB_INSTALL_DIR="$GPDB_INSTALL_DIR"
GPDB_DATA_DIR="$GPDB_DATA_DIR"
EOL

    log_success "Configuration saved to '$CONFIG_FILE'."
}

# --- Installation Step Functions (Stubs) ---

preflight_checks() {
    log_info "--- Step 1: Running Enhanced Pre-flight Checks ---"

    local coordinator_host="$GPDB_COORDINATOR_HOST"
    local segment_hosts=("${GPDB_SEGMENT_HOSTS[@]}") # Create a local copy to avoid modifying the global array

    # Add standby host to the list if it exists
    if [ -n "$GPDB_STANDBY_HOST" ]; then
        segment_hosts+=("$GPDB_STANDBY_HOST")
    fi

    local all_hosts=("${segment_hosts[@]}")

    # Basic checks
    check_os_compatibility "$all_hosts"
    check_sudo_privileges
    check_dependencies "$all_hosts"
    
    # Enhanced checks
    check_system_resources
    check_greenplum_compatibility
    check_library_versions
    check_network_connectivity

    log_success "Enhanced pre-flight checks completed."
}

check_os_compatibility() {
    local hosts=("${@}")
    for host in "${hosts[@]}"; do
        log_info "Checking OS compatibility on $host..."
        local os_release=$(ssh $host "cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null" | grep -E '^ID=' | cut -d'=' -f2 | tr -d '"')

        if [[ "$os_release" =~ ^(centos|rhel|rocky)$ ]]; then
            local os_version=$(ssh $host "cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null" | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
            if [[ "$os_version" =~ ^(7|8|9)$ ]]; then
                log_info "OS $os_release $os_version is compatible on $host."
            else
                log_error "Incompatible OS version on $host: $os_release $os_version. Only CentOS/RHEL/Rocky Linux 7, 8, or 9 are supported."
            fi
        else
            log_error "Unsupported OS on $host: $os_release. Only CentOS/RHEL/Rocky Linux are supported."
        fi
    done
}

check_dependencies() {
    local hosts=("${@}")
    # Add more dependencies as needed, e.g. 'tar', 'gzip'
    local required_dependencies=("sshpass" "sudo")

    for host in "${hosts[@]}"; do
        for dep in "${required_dependencies[@]}"; do
            # Special handling for sudo as it's often in /usr/bin or /usr/sbin
            if [[ "$dep" == "sudo" ]]; then
                log_info "Checking for dependency '$dep' on $host..."
                ssh $host "command -v sudo" >/dev/null 2>&1 && continue
                ssh $host "[ -f /usr/bin/sudo ]" >/dev/null 2>&1 && continue
                log_error "Dependency '$dep' not found on $host. Please install it."
            fi

            # Special handling for sshpass - try to install if not found
            if [[ "$dep" == "sshpass" ]]; then
                log_info "Checking for dependency '$dep' on $host..."
                if ssh $host "command -v $dep" >/dev/null 2>&1; then
                    log_success "sshpass found on $host"
                    continue
                else
                    log_warn "sshpass not found on $host. Attempting to install..."
                    
                    # Try to install sshpass using available package managers
                    local install_script="
                        if command -v yum >/dev/null 2>&1; then
                            echo 'Installing sshpass using yum...'
                            sudo yum install -y sshpass
                        elif command -v dnf >/dev/null 2>&1; then
                            echo 'Installing sshpass using dnf...'
                            sudo dnf install -y sshpass
                        elif command -v apt-get >/dev/null 2>&1; then
                            echo 'Installing sshpass using apt-get...'
                            sudo apt-get update && sudo apt-get install -y sshpass
                        else
                            echo 'No supported package manager found. Please install sshpass manually.'
                            exit 1
                        fi
                    "
                    
                    if ssh $host "$install_script"; then
                        log_success "sshpass installed successfully on $host"
                    else
                        log_error "Failed to install sshpass on $host. Please install it manually."
                    fi
                fi
            fi

            # For other dependencies, just check if they exist
            log_info "Checking for dependency '$dep' on $host..."
            ssh $host "command -v $dep" >/dev/null 2>&1 || log_error "Dependency '$dep' not found on $host. Please install it (e.g., 'yum install $dep' or 'apt-get install $dep')."
        done
    done
}

setup_hosts() {
    log_info "--- Step 2: Setting Up Hosts (User, Directories, SSH) ---"

    local all_hosts=($(get_all_hosts))

    log_info "This script needs to perform actions as root on all hosts."
    read -s -p "Please enter the password for a user with sudo access on all hosts: " SUDO_PASSWORD
    echo "" # Newline after password input
    if [ -z "$SUDO_PASSWORD" ]; then
        log_error "Sudo password cannot be empty."
    fi

    log_info "A 'gpadmin' user will be created. Please provide a password for it."
    read -s -p "Enter password for the new 'gpadmin' user: " GPADMIN_PASSWORD
    echo ""
    if [ -z "$GPADMIN_PASSWORD" ]; then
        log_error "gpadmin password cannot be empty."
    fi

    local total_hosts=${#all_hosts[@]}
    local current_host=0
    
    for host in "${all_hosts[@]}"; do
        ((current_host++))
        show_progress "Configuring hosts" "$current_host" "$total_hosts"
        log_info_with_timestamp "Configuring host: $host"
        create_gpadmin_user_and_dirs "$host" "$SUDO_PASSWORD" "$GPADMIN_PASSWORD"
    done
    echo "" # New line after progress bar

    setup_passwordless_ssh "$GPADMIN_PASSWORD" "${all_hosts[@]}"

    log_success "All hosts have been set up successfully."
}

get_all_hosts() {
    local all_hosts_with_dupes=("$GPDB_COORDINATOR_HOST" "${GPDB_SEGMENT_HOSTS[@]}")
    if [ -n "$GPDB_STANDBY_HOST" ]; then
        all_hosts_with_dupes+=("$GPDB_STANDBY_HOST")
    fi

    # Return a unique, sorted list of hosts
    echo "${all_hosts_with_dupes[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

create_gpadmin_user_and_dirs() {
    local host=$1
    local sudo_pass=$2
    local gpadmin_pass=$3

    log_info "Creating 'gpadmin' user and data directories on $host..."

    # Using a heredoc for the remote script is cleaner than a long one-liner.
    local remote_script="
        set -e
        echo \"--- Running setup as root on $host ---\"
        if ! getent group gpadmin > /dev/null; then
            echo \"Creating group gpadmin...\"
            groupadd gpadmin
        else
            echo \"Group gpadmin already exists.\"
        fi

        if ! id -u gpadmin > /dev/null 2>&1; then
            echo \"Creating user gpadmin...\"
            useradd -g gpadmin -m -d /home/gpadmin gpadmin
        else
            echo \"User gpadmin already exists.\"
        fi

        echo \"Setting password for gpadmin...\"
        echo \"gpadmin:$gpadmin_pass\" | chpasswd

        echo \"Creating directories...\"
        mkdir -p \"$GPDB_INSTALL_DIR\" \"$GPDB_DATA_DIR\"
        chown -R gpadmin:gpadmin \"$GPDB_INSTALL_DIR\" \"$GPDB_DATA_DIR\"
        chmod 755 \"$GPDB_INSTALL_DIR\"
        chmod 755 \"$GPDB_DATA_DIR\"
        echo \"--- Root setup on $host complete ---\"
    "

    log_info "Executing remote script on $host:"
    if ! execute_command ssh -t "$host" "echo '$sudo_pass' | sudo -S bash -c '$remote_script'"; then
        log_error "Failed to create gpadmin user and directories on $host."
        # The specific error message from the remote script is already captured and logged
        # by the enhanced `execute_command` function.  No need to repeat it here.
    fi

}

setup_passwordless_ssh() {
    local gpadmin_pass=$1
    shift
    local all_hosts=("$@")
    local coordinator_host="$GPDB_COORDINATOR_HOST"

    log_info "Setting up passwordless SSH for 'gpadmin' from $coordinator_host..."

    # Generate SSH key for gpadmin on the coordinator if it doesn't exist.
    log_info "Generating SSH key for gpadmin user..."
    if [ ! -f /home/gpadmin/.ssh/id_rsa ]; then
        execute_command sudo -u gpadmin ssh-keygen -t rsa -N "" -f /home/gpadmin/.ssh/id_rsa || log_error "Failed to generate SSH key for gpadmin user."
    else
        log_info "SSH key already exists for gpadmin user."
    fi

    for host in "${all_hosts[@]}"; do
        log_info "Copying SSH key to $host..."
        if ! execute_command sshpass -p "$gpadmin_pass" ssh-copy-id -o StrictHostKeyChecking=no "gpadmin@$host"; then
            log_error "Failed to copy SSH key to $host. Please ensure the gpadmin user exists and the password is correct."
        fi
    done

    log_info "Scanning all host keys to prevent interactive prompts..."

    # Create the known_hosts file if it doesn't exist
    execute_command sudo -u gpadmin mkdir -p /home/gpadmin/.ssh
    execute_command sudo -u gpadmin touch /home/gpadmin/.ssh/known_hosts

    execute_command sudo -u gpadmin ssh-keyscan -H "${all_hosts[@]}" >> /home/gpadmin/.ssh/known_hosts
    # Remove duplicate entries from known_hosts
    sudo -u gpadmin sort -u /home/gpadmin/.ssh/known_hosts -o /home/gpadmin/.ssh/known_hosts
}


install_greenplum() {
    log_info "--- Step 3: Installing Greenplum Binaries ---"

    local all_hosts=($(get_all_hosts))

    # --- 1. Detect Installer File ---
    log_info "Looking for Greenplum installer in '$INSTALL_FILES_DIR'..."
    local installer_file=$(find "$INSTALL_FILES_DIR" -maxdepth 1 -type f -name "greenplum-db-*.el*.x86_64.rpm" 2>/dev/null)
    # Supports el7, el8, el9 for CentOS/RHEL/Rocky Linux

    if [ -z "$installer_file" ]; then
        log_error "No Greenplum installer found in '$INSTALL_FILES_DIR'. Please ensure the installer file (greenplum-db-*.el*.x86_64.rpm) is present."
    elif [[ $(echo "$installer_file" | wc -l) -gt 1 ]]; then
        log_warn "Multiple installer files found. Using the first one: $installer_file"
        installer_file=$(echo "$installer_file" | head -n 1)
    fi

    log_success "Found installer: $(basename "$installer_file")"

    # --- 2. Distribute Installer ---
    for host in "${all_hosts[@]}"; do
        if [[ "$host" != "$GPDB_COORDINATOR_HOST" ]]; then # No need to copy to coordinator if installing from there
            log_info "Copying installer to $host..."
            execute_command scp "$installer_file" "$host:$GPDB_INSTALL_DIR" || log_error "Failed to copy installer to $host."
        fi
    done

    # --- 3. Install Binaries ---
    local total_hosts=${#all_hosts[@]}
    local current_host=0
    
    for host in "${all_hosts[@]}"; do
        ((current_host++))
        show_progress "Installing Greenplum binaries" "$current_host" "$total_hosts"
        log_info_with_timestamp "Installing Greenplum on $host..."

        local remote_installer_path="$GPDB_INSTALL_DIR/$(basename "$installer_file")"
        if [[ "$host" == "$GPDB_COORDINATOR_HOST" ]]; then
            remote_installer_path="$installer_file"  # Install directly if on coordinator and installer is already there
        fi

        # Check for existing Greenplum installation
        if ssh "$host" "test -d '$GPDB_INSTALL_DIR/greenplum-db-7'"; then
             log_warn_with_timestamp "Greenplum appears to be already installed in $GPDB_INSTALL_DIR on $host. Skipping installation."
             continue
        fi

        # Determine the package manager based on the OS (assuming CentOS/RHEL here)
        local remote_script="
            set -e
            echo \"--- Installing Greenplum on $host ---\"

            if rpm -q --quiet rpm; then
                echo \"Using rpm to install Greenplum...\"
                sudo rpm -ivh $remote_installer_path
            else
                echo \"rpm not found. Cannot proceed with installation on $host.\"
                exit 1
            fi
            echo \"--- Greenplum installation on $host complete ---
        "
        log_info_with_timestamp "Executing remote installation script on $host"
        execute_command ssh -t "$host" "$remote_script" || log_error_with_timestamp "Greenplum installation failed on $host"

        # Source the greenplum_path.sh file (needed for gpinitsystem later)
        #  This will likely need adjusting based on the actual path within the installed Greenplum directory
        #  It is also not persistent, so we will need to add it to the gpadmin user's .bashrc later
        #  Consider also adding logic to handle different Greenplum versions as part of the path.
        log_info_with_timestamp "Sourcing greenplum_path.sh on $host - this is a temporary setting."
        execute_command ssh "$host" "source $GPDB_INSTALL_DIR/greenplum-db-7/greenplum_path.sh"
    done
    echo "" # New line after progress bar

    log_success "Greenplum binaries installed on all hosts."
}

initialize_cluster() {
    log_info "--- Step 4: Initializing Greenplum Cluster ---"

    local coordinator_host="$GPDB_COORDINATOR_HOST"
    local all_hosts=($(get_all_hosts))

    # --- 1. Generate gpinitsystem_config ---
    log_info "Generating gpinitsystem_config file..."

    # Determine the segment prefix.  This assumes a simple sequential naming scheme (sdw1, sdw2, etc.)
    #  If a non-sequential or custom naming scheme is used, this will need adjustment.
    local segment_prefix
    if [[ ${#GPDB_SEGMENT_HOSTS[@]} -gt 1 ]]; then
        segment_prefix=$(echo "${GPDB_SEGMENT_HOSTS[0]}" | sed 's/[0-9]*$//') #remove trailing digits
    else
        segment_prefix="sdw" # Default prefix if only one segment host (or coordinator is the only host)
    fi

    local gpinitsystem_config="$GPDB_INSTALL_DIR/gpinitsystem_config"
    cat > "$gpinitsystem_config" <<EOL
ARRAY_NAME="TDI Greenplum Cluster"
SEG_PREFIX=$segment_prefix
PORT_BASE=40000
MASTER_HOSTNAME=$GPDB_COORDINATOR_HOST
MASTER_DIRECTORY=$GPDB_DATA_DIR/master
MASTER_PORT=5432
DATABASE_NAME=tdi

EOL

    # Add segment hosts and directories
    local i=0
    for host in "${GPDB_SEGMENT_HOSTS[@]}"; do
        echo "declare -a DATA_DIRECTORY=('$GPDB_DATA_DIR/primary$i')" >> "$gpinitsystem_config"
        if [[ "$host" == "$coordinator_host" && ${#GPDB_SEGMENT_HOSTS[@]} -gt 1 ]]; then
            # Special case: if the coordinator is also a segment, but not the *only* segment,
            #  we need to assign it a different port and hostname for the segment instance.
            echo "declare -a MACHINE_LIST=('${segment_prefix}$i')" >> "$gpinitsystem_config"  # e.g. sdw0
        else
            echo "declare -a MACHINE_LIST=('$host')" >> "$gpinitsystem_config"
        fi
        ((i++))
    done

    if [ -n "$GPDB_STANDBY_HOST" ]; then
        echo "STANDBY_MASTER_HOSTNAME=$GPDB_STANDBY_HOST" >> "$gpinitsystem_config"
    fi

    log_success "Generated gpinitsystem_config at $gpinitsystem_config"

    # --- 2. Run gpinitsystem ---
    log_info "Initializing Greenplum cluster with gpinitsystem..."
    execute_command ssh "$coordinator_host" "sudo -u gpadmin $GPDB_INSTALL_DIR/greenplum-db-7/bin/gpinitsystem -c $gpinitsystem_config -a" || log_error "gpinitsystem failed."

    # --- 3. Set up environment variables (persistent) ---
    log_info_with_timestamp "Setting up persistent environment variables for gpadmin on all hosts..."
    local env_setup="
if [ -f $GPDB_INSTALL_DIR/greenplum-db-7/greenplum_path.sh ]; then
    source $GPDB_INSTALL_DIR/greenplum-db-7/greenplum_path.sh
fi
export MASTER_HOST=$GPDB_COORDINATOR_HOST
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=tdi
"
    local total_hosts=${#all_hosts[@]}
    local current_host=0
    
    for host in "${all_hosts[@]}"; do
        ((current_host++))
        show_progress "Configuring environment" "$current_host" "$total_hosts"
        log_info_with_timestamp "Configuring environment on $host..."
        execute_command ssh "$host" "sudo -u gpadmin bash -c \"echo '$env_setup' >> /home/gpadmin/.bashrc\""
        # Also source it for the current session (though this only affects this script's execution)
        execute_command ssh "$host" "sudo -u gpadmin bash -c \"source /home/gpadmin/.bashrc\""
    done
    echo "" # New line after progress bar

    # --- 4. Configure pg_hba.conf ---
    log_info "Configuring pg_hba.conf on coordinator..."
    local pg_hba_path="$GPDB_DATA_DIR/master/pg_hba.conf" # Adjust this if necessary for different GPDB versions

    # Allow connections from all hosts in the cluster, using password authentication
    local pg_hba_entries=""
    for host in "${all_hosts[@]}"; do
        pg_hba_entries="$pg_hba_entries
host    all             all             $host/32                 password"
    done

    # Append the entries to pg_hba.conf
    execute_command ssh "$coordinator_host" "sudo -u gpadmin bash -c \"echo '$pg_hba_entries' >> $pg_hba_path\"" || log_error "Failed to update pg_hba.conf"

    # Restart Greenplum to apply pg_hba.conf changes
    log_info "Restarting Greenplum to apply pg_hba.conf changes..."
    execute_command ssh "$coordinator_host" "sudo -u gpadmin $GPDB_INSTALL_DIR/greenplum-db-7/bin/gpstop -ar"
    execute_command ssh "$coordinator_host" "sudo -u gpadmin $GPDB_INSTALL_DIR/greenplum-db-7/bin/gpstart -a" || log_error "Failed to restart Greenplum"

    log_success "Greenplum cluster initialized and configured."
}

# --- Main Execution ---
main() {
    echo -e "${COLOR_GREEN}Welcome to the Tanzu Greenplum Database Installer!${COLOR_RESET}"
    log_info_with_timestamp "Starting Greenplum installation process"
    
    # Create the directory for installer files if it doesn't exist.
    mkdir -p "$INSTALL_FILES_DIR"
    log_info_with_timestamp "Please place required installation files in the '$INSTALL_FILES_DIR' directory."

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                log_warn "Dry run mode enabled. No commands will be executed."
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                ;;
        esac
    done

    configure_installation

    # Load the configuration
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        log_info "Configuration loaded."
        validate_configuration
    else
        log_error "Configuration file '$CONFIG_FILE' not found. Exiting."
    fi
    
    # Execute installation steps
    preflight_checks
    setup_hosts
    install_greenplum
    initialize_cluster

    log_success_with_timestamp "All done! Your Greenplum Database cluster is ready."
}

# --- Help Function ---
show_help() {
    echo "Usage: $0 [OPTION]"
    echo "Options:"
    echo "  --dry-run     Enable dry-run mode (simulates installation without making changes)."
    echo "  --help        Show this help message."
}

# --- Progress indicator functions ---
show_progress() {
    local message="$1"
    local current="$2"
    local total="$3"
    local percentage=$((current * 100 / total))
    
    printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s: [%-50s] %d%% (%d/%d)" \
        "$message" \
        "$(printf '#%.0s' $(seq 1 $((percentage / 2))))" \
        "$percentage" \
        "$current" \
        "$total"
}

show_spinner() {
    local message="$1"
    local pid=$2
    local delay=0.1
    local spinstr='|/-\'
    
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s [%c] " "$message" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s [Done]    \n" "$message"
}

# --- Enhanced logging with timestamps ---
log_info_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_BLUE}[INFO][${timestamp}]${COLOR_RESET} $1"
}

log_success_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_GREEN}[SUCCESS][${timestamp}]${COLOR_RESET} $1"
}

log_warn_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_YELLOW}[WARN][${timestamp}]${COLOR_RESET} $1"
}

log_error_with_timestamp() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${COLOR_RED}[ERROR][${timestamp}]${COLOR_RESET} $1" >&2
    exit 1
}

# Run the main function
main "$@"