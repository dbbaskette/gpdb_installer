#!/bin/bash

# Greenplum library for Greenplum Installer
# Provides Greenplum-specific operations and cluster management

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"

# Function to detect Greenplum version from installer file
detect_greenplum_version() {
    local installer_file="$1"
    
    if [ -z "$installer_file" ] || [ ! -f "$installer_file" ]; then
        log_error "Installer file not provided or not found: $installer_file"
        return 1
    fi
    
    # Extract version from filename (e.g., greenplum-db-7.5.2-el9-x86_64.rpm -> 7.5.2)
    local version=$(basename "$installer_file" | sed -n 's/greenplum-db-\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
    
    if [ -z "$version" ]; then
        # Try alternative format (e.g., greenplum-db-7.0-el8-x86_64.rpm -> 7.0)
        version=$(basename "$installer_file" | sed -n 's/greenplum-db-\([0-9]\+\.[0-9]\+\).*/\1/p')
    fi
    
    if [ -z "$version" ]; then
        log_error "Could not detect Greenplum version from installer: $installer_file"
        return 1
    fi
    
    echo "$version"
}

# Function to setup GPHOME with proper versioning
setup_gphome() {
    local version="$1"
    
    if [ -z "$version" ]; then
        log_error "Greenplum version not provided for GPHOME setup"
        return 1
    fi
    
    # Set version-specific GPHOME
    local versioned_gphome="/usr/local/greenplum-db-$version"
    
    # Export GPHOME globally
    export GPHOME="$versioned_gphome"
    
    log_info "GPHOME set to: $GPHOME"
    echo "$GPHOME"
}

# Function to create GPHOME symlink for compatibility
create_gphome_symlink() {
    local host="$1"
    local versioned_gphome="$2"
    
    log_info "Creating GPHOME symlink on $host..."
    
    local symlink_script="
        if [ -L /usr/local/greenplum-db ] && [ -e /usr/local/greenplum-db ]; then
            echo 'Removing existing symlink...'
            sudo rm -f /usr/local/greenplum-db
        elif [ -d /usr/local/greenplum-db ] && [ ! -L /usr/local/greenplum-db ]; then
            echo 'Warning: /usr/local/greenplum-db exists as directory, not symlink'
            sudo mv /usr/local/greenplum-db /usr/local/greenplum-db.backup.\$(date +%s)
        fi
        
        if [ -d '$versioned_gphome' ]; then
            sudo ln -sf '$versioned_gphome' /usr/local/greenplum-db
            echo 'Symlink created: /usr/local/greenplum-db -> $versioned_gphome'
        else
            echo 'Error: Versioned directory $versioned_gphome not found'
            exit 1
        fi
    "
    
    if ssh_execute "$host" "$symlink_script"; then
        log_success "GPHOME symlink created on $host"
    else
        log_error "Failed to create GPHOME symlink on $host"
        return 1
    fi
}

# Function to find Greenplum installer file
find_greenplum_installer() {
    local install_files_dir="${1:-files}"
    
    log_info "Looking for Greenplum installer in '$install_files_dir'..." >&2
    
    local installer_file=$(find "$install_files_dir" -maxdepth 1 -type f -name "greenplum-db-*.rpm" 2>/dev/null | grep -v "clients" | head -n1)
    
    if [ -z "$installer_file" ]; then
        log_error "No Greenplum installer found in '$install_files_dir'. Please ensure the installer file (greenplum-db-*.el*.x86_64.rpm) is present." >&2
        return 1
    elif [[ $(echo "$installer_file" | wc -l) -gt 1 ]]; then
        log_warn "Multiple installer files found. Using the first one: $installer_file" >&2
        installer_file=$(echo "$installer_file" | head -n 1)
    fi
    
    echo "$installer_file"
}

# Function to distribute installer to hosts
distribute_installer() {
    local installer_file="$1"
    local hosts=("${@:2}")
    
    log_info "Distributing installer to hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Copying installer to $host..."
        if ! ssh_copy_file "$installer_file" "$host" "/tmp/"; then
            log_error "Failed to copy installer to $host"
        fi
    done
}

# Function to install Greenplum on a single host
install_greenplum_single() {
    local host="$1"
    local installer_file="$2"
    local sudo_password="$3"
    
    log_info_with_timestamp "Installing Greenplum on $host..."
    
    local remote_installer_path="/tmp/$(basename "$installer_file")"
    
    # Check for existing installation
    if ssh_execute "$host" "rpm -q greenplum-db-7 2>/dev/null"; then
        log_warn_with_timestamp "Greenplum appears to be already installed on $host. Skipping installation."
        return 0
    fi
    
    # Install dependencies and Greenplum
    local remote_script="
        set -e
        echo \"Installing Greenplum dependencies...\"
        echo '$sudo_password' | sudo -S dnf install -y apr apr-util krb5-devel libevent-devel perl python3-psycopg2 python3.11 readline-devel 2>/dev/null || echo '$sudo_password' | sudo -S yum install -y apr apr-util krb5-devel libevent-devel perl python3-psycopg2 python3.11 readline-devel
        
        echo \"Installing Greenplum...\"
        if echo '$sudo_password' | sudo -S rpm -q greenplum-db-7 2>/dev/null; then
            echo \"Greenplum is already installed.\"
        else
            # Remove existing greenplum-db directory if it exists
            if [ -e \"/usr/local/greenplum-db\" ]; then
                echo \"Removing existing greenplum-db directory...\"
                echo '$sudo_password' | sudo -S rm -rf \"/usr/local/greenplum-db\"
            fi
            echo '$sudo_password' | sudo -S yum install -y $remote_installer_path
        fi
    "
    
    if ssh_execute "$host" "$remote_script"; then
        # Create symlink for compatibility
        create_gphome_symlink "$host" "$GPHOME"
        setup_greenplum_environment "$host"
        return 0
    else
        log_error_with_timestamp "Greenplum installation failed on $host"
    fi
}

# Function to setup Greenplum environment on a host
setup_greenplum_environment() {
    local host="$1"
    
    log_info_with_timestamp "Setting up Greenplum environment on $host..."
    
    local setup_script="
        echo \"Setting up Greenplum environment...\"
        if [ -f \"$GPHOME/greenplum_path.sh\" ]; then
            source \"$GPHOME/greenplum_path.sh\"
            echo \"Greenplum environment sourced successfully\"
        else
            echo \"Warning: greenplum_path.sh not found in $GPHOME/\"
        fi
    "
    
    ssh_execute "$host" "$setup_script"
}

# Function to generate gpinitsystem configuration
generate_gpinitsystem_config() {
    local coordinator_host="$1"
    local segment_hosts=("${@:2}")
    
    log_info "Generating gpinitsystem_config file..." >&2
    
    # Determine segment prefix
    local segment_prefix
    if [[ ${#segment_hosts[@]} -gt 1 ]]; then
        segment_prefix=$(echo "${segment_hosts[0]}" | sed 's/[0-9]*$//')
    else
        segment_prefix="sdw"
    fi
    
    local gpinitsystem_config="/tmp/gpinitsystem_config"
    cat > "$gpinitsystem_config" <<EOL
ARRAY_NAME="TDI Greenplum Cluster"
SEG_PREFIX=$segment_prefix
PORT_BASE=40000
COORDINATOR_HOSTNAME=$coordinator_host
COORDINATOR_DIRECTORY=$GPDB_DATA_DIR/master
COORDINATOR_PORT=5432
DATABASE_NAME=tdi
ENCODING=UNICODE
LOCALE=en_US.utf8
CHECK_POINT_SEGMENTS=8
EOL
    
    # Create machine list file
    local machine_list_file="/tmp/machine_list"
    rm -f "$machine_list_file"
    
    declare -A unique_hosts
    for host in "${segment_hosts[@]}"; do
        unique_hosts["$host"]=1
    done
    
    for host in "${!unique_hosts[@]}"; do
        echo "$host" >> "$machine_list_file"
    done
    
    echo "MACHINE_LIST_FILE=$machine_list_file" >> "$gpinitsystem_config"
    
    # Add primary segment configuration
    echo -n "declare -a DATA_DIRECTORY=(" >> "$gpinitsystem_config"
    local i=0
    for host in "${segment_hosts[@]}"; do
        echo -n "$GPDB_DATA_DIR/primary$i " >> "$gpinitsystem_config"
        i=$((i + 1))
    done
    echo ")" >> "$gpinitsystem_config"
    
    # Add mirror configuration for multi-node setups
    if [ ${#segment_hosts[@]} -gt 1 ]; then
        echo -n "declare -a MIRROR_DATA_DIRECTORY=(" >> "$gpinitsystem_config"
        local j=0
        for host in "${segment_hosts[@]}"; do
            echo -n "$GPDB_DATA_DIR/mirror$j " >> "$gpinitsystem_config"
            j=$((j + 1))
        done
        echo ")" >> "$gpinitsystem_config"
        
        # Enable mirror segments
        echo "MIRROR_PORT_BASE=50000" >> "$gpinitsystem_config"
        echo "REPLICATION_PORT_BASE=51000" >> "$gpinitsystem_config"
        echo "MIRROR_REPLICATION_PORT_BASE=52000" >> "$gpinitsystem_config"
    fi
    
    if [ -n "$GPDB_STANDBY_HOST" ]; then
        echo "STANDBY_MASTER_HOSTNAME=$GPDB_STANDBY_HOST" >> "$gpinitsystem_config"
    fi
    
    log_success "Generated gpinitsystem_config at $gpinitsystem_config" >&2
    echo "$gpinitsystem_config"
}

# Function to create data directories on hosts
create_data_directories() {
    local hosts=("$@")
    
    log_info "Creating data directories on all hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Creating data directories on $host..."
        
        # Create master directory (only on coordinator)
        if [ "$host" = "$GPDB_COORDINATOR_HOST" ]; then
            ssh_execute "$host" "sudo -u gpadmin mkdir -p $GPDB_DATA_DIR/master"
            ssh_execute "$host" "sudo -u gpadmin chmod 755 $GPDB_DATA_DIR/master"
        fi
        
        # Create primary directories for segments
        local primary_count=0
        local mirror_count=0
        
        for segment_host in "${GPDB_SEGMENT_HOSTS[@]}"; do
            if [ "$segment_host" = "$host" ]; then
                # Create primary segment directory
                ssh_execute "$host" "sudo -u gpadmin mkdir -p $GPDB_DATA_DIR/primary$primary_count"
                ssh_execute "$host" "sudo -u gpadmin chmod 755 $GPDB_DATA_DIR/primary$primary_count"
                primary_count=$((primary_count + 1))
                
                # Create mirror directory (for production setups)
                # Mirrors are placed on different hosts in round-robin fashion
                local mirror_host_index=$((primary_count % ${#GPDB_SEGMENT_HOSTS[@]}))
                local mirror_host="${GPDB_SEGMENT_HOSTS[$mirror_host_index]}"
                
                # Only create mirror if it's on a different host (multi-node setup)
                if [ "$mirror_host" != "$host" ] && [ ${#GPDB_SEGMENT_HOSTS[@]} -gt 1 ]; then
                    log_info "Creating mirror directory for segment $primary_count on $mirror_host"
                    ssh_execute "$mirror_host" "sudo -u gpadmin mkdir -p $GPDB_DATA_DIR/mirror$mirror_count"
                    ssh_execute "$mirror_host" "sudo -u gpadmin chmod 755 $GPDB_DATA_DIR/mirror$mirror_count"
                    mirror_count=$((mirror_count + 1))
                fi
            fi
        done
    done
}

# Function to initialize Greenplum cluster
initialize_greenplum_cluster() {
    local coordinator_host="$1"
    local config_file="$2"
    local machine_list_file="$3"
    
    log_info "Initializing Greenplum cluster..."
    
    # Copy configuration files to coordinator
    ssh_copy_file "$config_file" "$coordinator_host" "/tmp/"
    ssh_copy_file "$machine_list_file" "$coordinator_host" "/tmp/"
    
    # Move files to gpadmin home with proper permissions
    ssh_execute "$coordinator_host" "sudo cp /tmp/gpinitsystem_config /home/gpadmin/ && sudo cp /tmp/machine_list /home/gpadmin/ && sudo chown gpadmin:gpadmin /home/gpadmin/gpinitsystem_config /home/gpadmin/machine_list"
    
    # Run gpinitsystem
    local init_command="cd /home/gpadmin && source $GPHOME/greenplum_path.sh && $GPHOME/bin/gpinitsystem -c /home/gpadmin/gpinitsystem_config -a"
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c '$init_command'"; then
        log_success "Greenplum cluster initialized successfully"
    else
        log_error "gpinitsystem failed"
    fi
}

# Function to setup persistent environment for gpadmin
setup_gpadmin_environment() {
    local hosts=("$@")
    
    log_info_with_timestamp "Setting up persistent environment variables for gpadmin..."
    
    local env_setup="
# Greenplum Environment Setup - Auto-generated by installer
if [ -f $GPHOME/greenplum_path.sh ]; then
    source $GPHOME/greenplum_path.sh
fi
export MASTER_HOST=$GPDB_COORDINATOR_HOST
export COORDINATOR_DATA_DIRECTORY=$GPDB_DATA_DIR/master/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=tdi
"
    
    for host in "${hosts[@]}"; do
        log_info_with_timestamp "Configuring environment on $host..."
        
        # Create environment setup script to prevent duplicates
        local env_script="
        # Check if Greenplum environment is already configured
        if ! grep -q 'Greenplum Environment Setup' /home/gpadmin/.bash_profile 2>/dev/null; then
            echo 'Adding Greenplum environment to .bash_profile...'
            echo '$env_setup' >> /home/gpadmin/.bash_profile
        else
            echo 'Greenplum environment already configured in .bash_profile'
        fi
        
        # Also update .bashrc for interactive shell compatibility
        if ! grep -q 'Greenplum Environment Setup' /home/gpadmin/.bashrc 2>/dev/null; then
            echo 'Adding Greenplum environment to .bashrc...'
            echo '$env_setup' >> /home/gpadmin/.bashrc
        else
            echo 'Greenplum environment already configured in .bashrc'
        fi
        
        # Ensure proper ownership
        chown gpadmin:gpadmin /home/gpadmin/.bash_profile /home/gpadmin/.bashrc 2>/dev/null || true
        "
        
        ssh_execute "$host" "sudo -u gpadmin bash -c \"$env_script\""
    done
}

# Function to configure pg_hba.conf
configure_pg_hba() {
    local coordinator_host="$1"
    local hosts=("${@:2}")
    
    log_info "Configuring pg_hba.conf on coordinator..."
    
    # Find the actual master directory (it could be gpseg-1, sdw-1, etc.)
    local master_dir_script="
    find $GPDB_DATA_DIR/master -name 'pg_hba.conf' -type f | head -n1 | xargs dirname
    "
    local master_dir=$(ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c \"$master_dir_script\"" | tr -d '\r\n')
    
    if [ -z "$master_dir" ]; then
        log_error "Could not locate master data directory"
        return 1
    fi
    
    local pg_hba_path="$master_dir/pg_hba.conf"
    log_info "Master directory found at: $master_dir"
    
    # Create comprehensive pg_hba.conf entries
    local pg_hba_entries="
# Greenplum Database pg_hba.conf entries - Auto-generated by installer

# Local connections (trust for gpadmin operations)
local   all             gpadmin                                 trust
local   all             all                                     md5

# IPv4 local connections
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust

# Replication connections for segments
local   replication     gpadmin                                 trust
host    replication     gpadmin         127.0.0.1/32            trust
host    replication     gpadmin         ::1/128                 trust"
    
    # Add entries for all cluster hosts
    for host in "${hosts[@]}"; do
        # Resolve hostname to IP if possible
        local host_ip=$(ssh_execute "$coordinator_host" "getent hosts $host | awk '{print \$1}' | head -n1" 2>/dev/null || echo "$host")
        
        pg_hba_entries="$pg_hba_entries
# Connections from $host
host    all             all             $host_ip/32             md5
host    replication     gpadmin         $host_ip/32             trust"
        
        # If host is not an IP, also add hostname-based entry
        if [[ ! "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            pg_hba_entries="$pg_hba_entries
host    all             all             $host/32                md5"
        fi
    done
    
    # Backup existing pg_hba.conf and update
    local update_script="
    if [ -f '$pg_hba_path' ]; then
        echo 'Backing up original pg_hba.conf...'
        cp '$pg_hba_path' '$pg_hba_path.backup.\$(date +%s)'
        echo 'Adding Greenplum configuration entries...'
        echo '$pg_hba_entries' >> '$pg_hba_path'
        echo 'pg_hba.conf updated successfully'
    else
        echo 'Error: pg_hba.conf not found at $pg_hba_path'
        exit 1
    fi
    "
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c \"$update_script\""; then
        log_success "pg_hba.conf configured with proper trust and authentication entries"
    else
        log_error "Failed to configure pg_hba.conf"
        return 1
    fi
}

# Function to restart Greenplum cluster
restart_greenplum_cluster() {
    local coordinator_host="$1"
    
    log_info "Restarting Greenplum to apply configuration changes..."
    
    local restart_command="cd /home/gpadmin && source $GPHOME/greenplum_path.sh && $GPHOME/bin/gpstop -ar && $GPHOME/bin/gpstart -a"
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c '$restart_command'"; then
        log_success "Greenplum cluster restarted successfully"
    else
        log_error "Failed to restart Greenplum cluster"
    fi
}

# Function to test Greenplum cluster connectivity
test_greenplum_connectivity() {
    local coordinator_host="$1"
    
    log_info "Testing Greenplum cluster connectivity..."
    
    local test_command="cd /home/gpadmin && source $GPHOME/greenplum_path.sh && psql -d tdi -c 'SELECT version();'"
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c '$test_command'"; then
        log_success "Greenplum cluster connectivity test passed"
        return 0
    else
        log_warn "Greenplum cluster connectivity test failed"
        return 1
    fi
}