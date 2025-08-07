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
        echo '$sudo_password' | sudo -S dnf install -y apr apr-util krb5-devel libevent-devel perl python3-psycopg2 python3.11 readline-devel java-11-openjdk-devel 2>/dev/null || echo '$sudo_password' | sudo -S yum install -y apr apr-util krb5-devel libevent-devel perl python3-psycopg2 python3.11 readline-devel java-11-openjdk-devel
        
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
    log_info "Debug: COORDINATOR_DATA_DIR='$COORDINATOR_DATA_DIR'" >&2
    log_info "Debug: SEGMENT_DATA_DIR='$SEGMENT_DATA_DIR'" >&2
    log_info "Debug: MIRROR_DATA_DIR='$MIRROR_DATA_DIR'" >&2
    
    # Use standard Greenplum segment prefix
    local segment_prefix="gpseg"
    
    local gpinitsystem_config="/tmp/gpinitsystem_config"
    cat > "$gpinitsystem_config" <<EOL
ARRAY_NAME="TDI Greenplum Cluster"
SEG_PREFIX=$segment_prefix
PORT_BASE=40000
COORDINATOR_HOSTNAME=$coordinator_host
COORDINATOR_DIRECTORY=$COORDINATOR_DATA_DIR
COORDINATOR_PORT=5432
DATABASE_NAME=tdi
ENCODING=UNICODE
LOCALE=en_US.UTF-8
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
    
    # Add primary segment configuration (single array with all directories)
    echo -n "declare -a DATA_DIRECTORY=(" >> "$gpinitsystem_config"
    local i=0
    for host in "${segment_hosts[@]}"; do
        echo -n "$SEGMENT_DATA_DIR/seg$i " >> "$gpinitsystem_config"
        i=$((i + 1))
    done
    echo ")" >> "$gpinitsystem_config"
    
    # Add mirror configuration for multi-node setups
    if [ ${#segment_hosts[@]} -gt 1 ]; then
        echo -n "declare -a MIRROR_DATA_DIRECTORY=(" >> "$gpinitsystem_config"
        local j=0
        for host in "${segment_hosts[@]}"; do
            echo -n "$MIRROR_DATA_DIR/seg$j " >> "$gpinitsystem_config"
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
    
    # Debug: show what we generated
    log_info "=== Generated configuration content ===" >&2
    cat "$gpinitsystem_config" >&2
    log_info "=== End configuration ===" >&2
    
    log_success "Generated gpinitsystem_config at $gpinitsystem_config" >&2
    echo "$gpinitsystem_config"
}

# Function to create data directories on hosts
create_data_directories() {
    local hosts=("$@")
    
    log_info "Creating specific segment data directories on all hosts..."
    
    # Create coordinator segment directory
    log_info "Creating coordinator segment directory on $GPDB_COORDINATOR_HOST..."
    ssh_execute "$GPDB_COORDINATOR_HOST" "sudo -u gpadmin mkdir -p $COORDINATOR_DATA_DIR/gpseg-1"
    ssh_execute "$GPDB_COORDINATOR_HOST" "sudo -u gpadmin chmod 755 $COORDINATOR_DATA_DIR/gpseg-1"
    
    # Create primary segment directories to match the configuration file exactly
    # Each segment host gets ALL segment directories (gpinitsystem will use them as needed)
    local total_segments=${#GPDB_SEGMENT_HOSTS[@]}
    
    for segment_host in "${GPDB_SEGMENT_HOSTS[@]}"; do
        log_info "Creating segment directories on $segment_host..."
        
        # Create all segment directories on each host
        for ((seg_id=0; seg_id<total_segments; seg_id++)); do
            log_info "Creating primary segment directory seg$seg_id on $segment_host..."
            ssh_execute "$segment_host" "sudo -u gpadmin mkdir -p $SEGMENT_DATA_DIR/seg$seg_id"
            ssh_execute "$segment_host" "sudo -u gpadmin chmod 755 $SEGMENT_DATA_DIR/seg$seg_id"
        done
        
        # Create mirror directories (always create them to ensure availability)
        for ((seg_id=0; seg_id<total_segments; seg_id++)); do
            log_info "Creating mirror directory seg$seg_id on $segment_host..."
            ssh_execute "$segment_host" "sudo -u gpadmin mkdir -p $MIRROR_DATA_DIR/seg$seg_id"
            ssh_execute "$segment_host" "sudo -u gpadmin chmod 755 $MIRROR_DATA_DIR/seg$seg_id"
        done
    done
}

# Function to initialize Greenplum cluster
initialize_greenplum_cluster() {
    local coordinator_host="$1"
    local config_file="$2"
    local machine_list_file="$3"
    
    log_info "Initializing Greenplum cluster..."
    
    # Remove any existing configuration files from gpadmin home only
    ssh_execute "$coordinator_host" "sudo rm -f /home/gpadmin/gpinitsystem_config /home/gpadmin/machine_list"
    
    # Copy configuration files to coordinator
    ssh_copy_file "$config_file" "$coordinator_host" "/tmp/"
    ssh_copy_file "$machine_list_file" "$coordinator_host" "/tmp/"
    
    # Move files to gpadmin home with proper permissions
    ssh_execute "$coordinator_host" "sudo cp /tmp/gpinitsystem_config /home/gpadmin/ && sudo cp /tmp/machine_list /home/gpadmin/ && sudo chown gpadmin:gpadmin /home/gpadmin/gpinitsystem_config /home/gpadmin/machine_list"
    
    # Create a script file for gpinitsystem to avoid quoting issues
    local gpinit_script="/tmp/gpinitsystem_script.sh"
    cat > "$gpinit_script" << 'GPINIT_EOF'
#!/bin/bash
set -e
cd /home/gpadmin

# Set GPHOME from parameter
export GPHOME="$1"
echo "GPHOME set to: $GPHOME"

# Source Greenplum environment
if [ -f "$GPHOME/greenplum_path.sh" ]; then
    source "$GPHOME/greenplum_path.sh"
    echo "Greenplum environment sourced successfully"
else
    echo "ERROR: greenplum_path.sh not found at $GPHOME/greenplum_path.sh"
    exit 1
fi

# Verify gpinitsystem is available
if [ -x "$GPHOME/bin/gpinitsystem" ]; then
    echo "Found gpinitsystem at $GPHOME/bin/gpinitsystem"
else
    echo "ERROR: gpinitsystem not found or not executable at $GPHOME/bin/gpinitsystem"
    exit 1
fi

# Clean up any existing Greenplum data directories first
echo "Cleaning up any existing Greenplum data directories..."

# Clean up any existing data directories based on common patterns
# This is more robust than parsing the config file
echo "Removing any existing coordinator directories..."
rm -rf /home/gpdata/coordinator/* 2>/dev/null || true
rm -rf /home/gpdata/primary/* 2>/dev/null || true  
rm -rf /home/gpdata/mirror/* 2>/dev/null || true
rm -rf /data/coordinator/* 2>/dev/null || true
rm -rf /data/primary/* 2>/dev/null || true
rm -rf /data/mirror/* 2>/dev/null || true

# Also clean up any gpdb specific processes that might be running
echo "Stopping any existing Greenplum processes..."
pkill -f "postgres.*gp" 2>/dev/null || true
pkill -f "gpsync" 2>/dev/null || true

# Remove any existing shared memory and semaphores
echo "Cleaning up shared memory..."
ipcs -m | grep gpadmin | awk '{print $2}' | xargs -r ipcrm -m 2>/dev/null || true
ipcs -s | grep gpadmin | awk '{print $2}' | xargs -r ipcrm -s 2>/dev/null || true

echo "Cleanup completed."

# Debug: Show the config file content
echo "=== Configuration file content ==="
cat /home/gpadmin/gpinitsystem_config
echo "=== End configuration ==="

# Run gpinitsystem
echo "Running gpinitsystem..."
timeout 600 "$GPHOME/bin/gpinitsystem" -c /home/gpadmin/gpinitsystem_config -a

# If gpinitsystem timed out, check if cluster is actually working
if [ $? -eq 124 ]; then
    echo "gpinitsystem timed out, checking if cluster is actually running..."
    sleep 5
    
    # Set environment variables for testing
    export COORDINATOR_DATA_DIRECTORY=/home/gpdata/coordinator/gpseg-1
    export MASTER_HOST=$(hostname -f)
    
    # Test if we can connect to the database
    if psql -d tdi -c "SELECT 'Cluster is working!' as status;" 2>/dev/null; then
        echo "SUCCESS: Cluster is running despite timeout!"
        exit 0
    else
        echo "Attempting to start cluster manually..."
        if gpstart -a; then
            echo "SUCCESS: Cluster started manually!"
            exit 0
        else
            echo "FAILED: Could not start cluster"
            exit 1
        fi
    fi
fi
GPINIT_EOF
    
    # Copy script to coordinator and execute
    log_info "Executing gpinitsystem with GPHOME=$GPHOME"
    ssh_copy_file "$gpinit_script" "$coordinator_host" "/tmp/"
    
    # Execute with timeout to prevent hanging
    log_info "Starting gpinitsystem (this may take several minutes)..."
    if ssh_execute "$coordinator_host" "chmod +x /tmp/gpinitsystem_script.sh && timeout 600 sudo -u gpadmin /tmp/gpinitsystem_script.sh '$GPHOME' && rm -f /tmp/gpinitsystem_script.sh" "" "300"; then
        log_success "Greenplum cluster initialized successfully"
    else
        log_warn "gpinitsystem timed out or encountered an error"
        log_info "Checking if cluster was actually created successfully..."
        
        # Check if cluster is running despite timeout
        if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c 'source ~/.bashrc && gpstate -s'" "30" "true" 2>/dev/null; then
            log_success "Cluster appears to be running successfully despite timeout"
        else
            log_info "Attempting to start cluster..."
            if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c 'source $GPHOME/greenplum_path.sh && gpstart -a'" "60" "true" 2>/dev/null; then
                log_success "Cluster started successfully"
            else
                log_error "gpinitsystem failed - cluster is not running"
                return 1
            fi
        fi
    fi
    
    # Clean up local script
    rm -f "$gpinit_script"
}

# Function to setup persistent environment for gpadmin
setup_gpadmin_environment() {
    local hosts=("$@")
    
    log_info_with_timestamp "Setting up persistent environment variables for gpadmin..."
    
    for host in "${hosts[@]}"; do
        log_info_with_timestamp "Configuring environment on $host..."
        
        # Create a temporary script file to avoid quoting issues
        local temp_script="/tmp/setup_gp_env_$$.sh"
        cat > "$temp_script" << 'EOF'
#!/bin/bash

# Add Greenplum environment to .bashrc if not already present
if ! grep -q "Greenplum Environment Setup" /home/gpadmin/.bashrc 2>/dev/null; then
    cat >> /home/gpadmin/.bashrc << 'GPENV_EOF'

# Greenplum Environment Setup - Auto-generated by installer
source /usr/local/greenplum-db-7.5.2/greenplum_path.sh
export COORDINATOR_DATA_DIRECTORY=/home/gpdata/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=tdi
export LD_PRELOAD=/lib64/libz.so.1 ps
GPENV_EOF
    echo "Greenplum environment added to .bashrc"
else
    echo "Greenplum environment already configured in .bashrc"
fi

# Add to .bash_profile as well  
if ! grep -q "Greenplum Environment Setup" /home/gpadmin/.bash_profile 2>/dev/null; then
    cat >> /home/gpadmin/.bash_profile << 'GPENV_EOF'

# Greenplum Environment Setup - Auto-generated by installer
source /usr/local/greenplum-db-7.5.2/greenplum_path.sh
export COORDINATOR_DATA_DIRECTORY=/home/gpdata/coordinator/gpseg-1
export PGPORT=5432
export PGUSER=gpadmin
export PGDATABASE=tdi
export LD_PRELOAD=/lib64/libz.so.1 ps
GPENV_EOF
    echo "Greenplum environment added to .bash_profile"
else
    echo "Greenplum environment already configured in .bash_profile"
fi

chown gpadmin:gpadmin /home/gpadmin/.bash_profile /home/gpadmin/.bashrc
EOF
        
        # Copy script to host and execute
        ssh_copy_file "$temp_script" "$host" "/tmp/"
        ssh_execute "$host" "sudo bash /tmp/$(basename $temp_script) && rm -f /tmp/$(basename $temp_script)"
        
        # Clean up local temp script
        rm -f "$temp_script"
    done
}

# Function to configure pg_hba.conf
configure_pg_hba() {
    local coordinator_host="$1"
    local hosts=("${@:2}")
    
    log_info "Configuring pg_hba.conf on coordinator..."
    
    # Find the actual coordinator directory (it could be gpseg-1, etc.)
    local master_dir_script="
    find $COORDINATOR_DATA_DIR -name 'pg_hba.conf' -type f | head -n1 | xargs dirname
    "
    local master_dir=$(ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c \"$master_dir_script\"" "" "true" | tr -d '\r\n')
    
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
        local host_ip=$(ssh_execute "$coordinator_host" "getent hosts $host | awk '{print \$1}' | head -n1" "" "true" 2>/dev/null || echo "$host")
        
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
    
    # Add entries for allowed client subnets
    if [ ${#GPDB_ALLOWED_CLIENT_SUBNETS[@]} -gt 0 ]; then
        pg_hba_entries="$pg_hba_entries

# Allowed client connections from external subnets
"
        for subnet in "${GPDB_ALLOWED_CLIENT_SUBNETS[@]}"; do
            pg_hba_entries="$pg_hba_entries
host    all             all             $subnet             md5"
        done
    fi

    # Backup existing pg_hba.conf and update
    local update_script="
    if [ -f '$pg_hba_path' ]; then
        echo 'Backing up original pg_hba.conf to $pg_hba_path.backup.installer...'
        mv '$pg_hba_path' '$pg_hba_path.backup.installer'
        echo 'Creating new pg_hba.conf with correct access rules...'
        echo '$pg_hba_entries' > '$pg_hba_path'
        chmod 600 '$pg_hba_path'
        echo 'pg_hba.conf created successfully'
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
    
    local restart_command="
        cd /home/gpadmin
        source ~/.bashrc
        gpstop -ar
        gpstart -a
    "
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c '$restart_command'"; then
        log_success "Greenplum cluster restarted successfully"
    else
        log_warn "Failed to restart Greenplum cluster after pg_hba.conf update"
        log_info "Cluster was running successfully before restart - pg_hba.conf changes will take effect on next manual restart"
        log_info "You can manually restart with: sudo -u gpadmin bash -c 'source ~/.bashrc && gpstop -a && gpstart -a'"
    fi
}

# Function to test Greenplum cluster connectivity
test_greenplum_connectivity() {
    local coordinator_host="$1"
    
    log_info "Testing Greenplum cluster connectivity..."
    
    local test_command="
        cd /home/gpadmin
        source ~/.bashrc
        psql -d tdi -c \"SELECT version();\""
    
    if ssh_execute "$coordinator_host" "sudo -u gpadmin bash -c '$test_command'"; then
        log_success "Greenplum cluster connectivity test passed"
        return 0
    else
        log_warn "Greenplum cluster connectivity test failed"
        return 1
    fi
}