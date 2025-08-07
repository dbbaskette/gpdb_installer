#!/bin/bash

# SSH library for Greenplum Installer
# Provides SSH-related operations and connection management

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/validation.sh"

# SSH connection reuse settings
SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"
SSH_CONTROL_PERSIST="30m"  # Increased from 10m to 30m
SSH_TIMEOUT=30

# Global array to track established SSH connections
declare -a ESTABLISHED_SSH_HOSTS=()

# Function to refresh SSH connections if they're lost
refresh_ssh_connections() {
    local hosts=("$@")
    
    log_info "Refreshing SSH connections to ensure they're still active..."
    
    for host in "${hosts[@]}"; do
        # Check if connection is still alive
        if ! ssh -o ControlPath="$SSH_CONTROL_PATH" -O check "$host" 2>/dev/null; then
            log_warn "SSH connection to $host appears lost, re-establishing..."
            # Try to re-establish the connection
            establish_ssh_connection "$host"
        fi
    done
}

# Function to install sshpass if not available
install_sshpass() {
    log_info "Attempting to install sshpass..."
    
    # Try different package managers
    if command -v yum >/dev/null 2>&1; then
        if sudo yum install -y sshpass 2>/dev/null; then
            log_success "sshpass installed via yum"
            return 0
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if sudo dnf install -y sshpass 2>/dev/null; then
            log_success "sshpass installed via dnf"
            return 0
        fi
    elif command -v apt-get >/dev/null 2>&1; then
        if sudo apt-get update && sudo apt-get install -y sshpass 2>/dev/null; then
            log_success "sshpass installed via apt-get"
            return 0
        fi
    elif command -v brew >/dev/null 2>&1; then
        if brew install sshpass 2>/dev/null; then
            log_success "sshpass installed via brew"
            return 0
        fi
    fi
    
    log_warn "Could not install sshpass automatically. Please install it manually:"
    log_info "  RHEL/CentOS: sudo yum install sshpass"
    log_info "  Ubuntu/Debian: sudo apt-get install sshpass"
    log_info "  macOS: brew install sshpass"
    return 1
}

# Function to build SSH command with multiplexing options
build_ssh_cmd() {
    local user="${1:-root}"  # Default to root user for Greenplum installation
    local ssh_cmd="ssh"
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no"
    ssh_cmd="$ssh_cmd -o UserKnownHostsFile=/dev/null"
    ssh_cmd="$ssh_cmd -o ConnectTimeout=$SSH_TIMEOUT"
    ssh_cmd="$ssh_cmd -o ServerAliveInterval=60"
    ssh_cmd="$ssh_cmd -o ServerAliveCountMax=3"
    ssh_cmd="$ssh_cmd -o ControlMaster=auto"
    ssh_cmd="$ssh_cmd -o ControlPath=$SSH_CONTROL_PATH"
    ssh_cmd="$ssh_cmd -o ControlPersist=$SSH_CONTROL_PERSIST"
    ssh_cmd="$ssh_cmd -l $user"
    echo "$ssh_cmd"
}

# Function to establish SSH master connection
establish_ssh_connection() {
    local host="$1"
    
    log_info "Establishing SSH master connection to $host..."
    
    # Clean up any existing socket for this host first
    local socket_path=$(echo "$SSH_CONTROL_PATH" | sed "s/%h/$host/g" | sed "s/%p/22/g" | sed "s/%r/root/g")
    
    # Check if connection already exists and is working
    if [ -S "$socket_path" ]; then
        log_info "Existing SSH control socket found for $host, testing connection..."
        if ssh -o ControlPath="$SSH_CONTROL_PATH" -l root -O check "$host" 2>/dev/null; then
            log_success "Existing SSH master connection to $host is working"
            # Make sure it's in our tracking array
            if ! [[ " ${ESTABLISHED_SSH_HOSTS[*]} " =~ " $host " ]]; then
                ESTABLISHED_SSH_HOSTS+=("$host")
            fi
            return 0
        else
            log_info "Existing connection not working, cleaning up..."
            # Try to cleanly close existing connection
            ssh -o ControlPath="$SSH_CONTROL_PATH" -l root -O exit "$host" 2>/dev/null || true
            sleep 1
        fi
    fi
    rm -f "$socket_path" 2>/dev/null || true
    
    # Build SSH command for master connection (without auto mode)
    local master_ssh_cmd="ssh"
    master_ssh_cmd="$master_ssh_cmd -o StrictHostKeyChecking=no"
    master_ssh_cmd="$master_ssh_cmd -o UserKnownHostsFile=/dev/null"
    master_ssh_cmd="$master_ssh_cmd -o ConnectTimeout=30"
    master_ssh_cmd="$master_ssh_cmd -o ServerAliveInterval=60"
    master_ssh_cmd="$master_ssh_cmd -o ServerAliveCountMax=3"
    master_ssh_cmd="$master_ssh_cmd -o ControlMaster=yes"
    master_ssh_cmd="$master_ssh_cmd -o ControlPath=$SSH_CONTROL_PATH"
    master_ssh_cmd="$master_ssh_cmd -o ControlPersist=$SSH_CONTROL_PERSIST"
    master_ssh_cmd="$master_ssh_cmd -l root"
    
    # Create persistent SSH connection 
    if [ -n "$SSH_PASSWORD" ]; then
        log_info "Creating master SSH connection using stored password..."
        # Check if sshpass is available
        if command -v sshpass >/dev/null 2>&1; then
            log_info "Using sshpass for automated password authentication"
            if sshpass -e $master_ssh_cmd -N -f "$host"; then
                log_info "SSH master connection established using stored password"
                # Brief pause to ensure connection is established
                sleep 2
                
                # Verify the master connection is working
                if ssh_execute "$host" "echo 'Connection test successful'" >/dev/null 2>&1; then
                    log_success "SSH master connection verified and working for $host"
                    ESTABLISHED_SSH_HOSTS+=("$host")
                    return 0
                else
                    log_error "SSH master connection created but verification failed for $host"
                    return 1
                fi
            else
                log_warn "Failed to establish master connection to $host using stored password. Will prompt for password."
            fi
        else
            log_warn "sshpass not available. Installing sshpass for automated password authentication..."
            # Try to install sshpass
            if install_sshpass; then
                log_info "sshpass installed successfully. Retrying connection..."
                if sshpass -e $master_ssh_cmd -N -f "$host"; then
                    log_success "SSH master connection established using stored password"
                    ESTABLISHED_SSH_HOSTS+=("$host")
                    return 0
                fi
            fi
            log_warn "Will prompt for password manually for this connection"
        fi
    fi
    
    # Fallback to manual password entry
    log_info "Creating master SSH connection (will prompt for password)..."
    if $master_ssh_cmd -N -f "$host"; then
        log_info "SSH master connection established and ready for reuse"
        # Brief pause to ensure connection is established
        sleep 2
        
        # Verify the master connection is working (should use existing connection)
        if ssh_execute "$host" "echo 'Connection test successful'" >/dev/null 2>&1; then
            log_success "SSH master connection verified and working for $host"
            ESTABLISHED_SSH_HOSTS+=("$host")
            return 0
        else
            log_error "SSH master connection created but verification failed for $host"
            return 1
        fi
    else
        log_warn "Failed to establish master connection to $host. SSH will work but may prompt for passwords."
        return 1
    fi
}

# Function to establish connections to all hosts
establish_ssh_connections() {
    local hosts=("$@")
    
    log_info "Establishing SSH connections to all hosts to avoid repeated password prompts..."
    
    local success_count=0
    local total_count=${#hosts[@]}
    
    for host in "${hosts[@]}"; do
        if establish_ssh_connection "$host"; then
            success_count=$((success_count + 1))
        else
            log_warn "SSH connection multiplexing not available for $host (will still work but may prompt for passwords)"
        fi
    done
    
    if [ $success_count -eq $total_count ]; then
        log_success "All SSH master connections established successfully"
    elif [ $success_count -gt 0 ]; then
        log_info "SSH master connections established for $success_count out of $total_count hosts"
        log_info "Remaining hosts will use standard SSH connections"
    else
        log_warn "No SSH master connections could be established. SSH will work but may prompt for passwords repeatedly."
    fi
    
    return 0  # Don't fail the installation if SSH multiplexing doesn't work
}

# Function to check and re-establish SSH connections if needed
ensure_ssh_connections() {
    local hosts=("$@")
    
    log_info "Checking SSH master connections..."
    
    local failed_hosts=()
    for host in "${hosts[@]}"; do
        local socket_path=$(echo "$SSH_CONTROL_PATH" | sed "s/%h/$host/g" | sed "s/%p/22/g" | sed "s/%r/${USER:-$LOGNAME}/g")
        
        # Check if socket exists and connection is working
        if [ -S "$socket_path" ]; then
            if ssh_execute "$host" "echo 'Connection test successful'" >/dev/null 2>&1; then
                continue  # Connection is working
            fi
        fi
        
        log_warn "SSH master connection lost for $host, attempting to re-establish..."
        if establish_ssh_connection "$host"; then
            log_success "SSH master connection re-established for $host"
        else
            failed_hosts+=("$host")
        fi
    done
    
    if [ ${#failed_hosts[@]} -gt 0 ]; then
        log_warn "Could not re-establish SSH master connections for: ${failed_hosts[*]}"
        log_info "These hosts will use standard SSH connections (may prompt for passwords)"
    fi
}

# Function to cleanup SSH connections
cleanup_ssh_connections() {
    log_info "Cleaning up SSH connections..."
    
    for host in "${ESTABLISHED_SSH_HOSTS[@]}"; do
        local ssh_cmd=$(build_ssh_cmd)
        $ssh_cmd -O exit "$host" 2>/dev/null || true
    done
    
    # Clean up any remaining socket files
    rm -f /tmp/ssh_mux_* 2>/dev/null || true
    
    ESTABLISHED_SSH_HOSTS=()
}

# Function to clean up all SSH master connections and processes
cleanup_all_ssh_connections() {
    log_info "Cleaning up all SSH master connections and processes..."
    
    # Find and clean up any SSH control sockets
    find /tmp -name "ssh_mux_*" -type s 2>/dev/null | while read socket; do
        if [ -S "$socket" ]; then
            log_info "Cleaning up SSH socket: $socket"
            # Extract host info from socket name if possible
            local host_info=$(basename "$socket" | sed 's/ssh_mux_//' | cut -d'_' -f1)
            if [ -n "$host_info" ]; then
                ssh -o ControlPath="$socket" -O exit "$host_info" 2>/dev/null || true
            fi
            rm -f "$socket" 2>/dev/null || true
        fi
    done
    
    # Kill any hanging SSH master processes (more targeted)
    pkill -f "ssh.*ControlMaster.*yes" 2>/dev/null || true
    pkill -f "ssh.*ControlPersist" 2>/dev/null || true
    
    # Also kill any SSH processes that might be stuck with our control path pattern
    pgrep -f "ssh.*${SSH_CONTROL_PATH}" | xargs kill 2>/dev/null || true
    
    # Wait a moment for cleanup
    sleep 3
    
    # Final cleanup of any remaining socket files
    rm -f /tmp/ssh_mux_* 2>/dev/null || true
    
    ESTABLISHED_SSH_HOSTS=()
    log_info "SSH connection cleanup completed"
}

# Function to cleanup SSH connections on remote hosts
cleanup_remote_ssh_connections() {
    local hosts=("$@")
    
    log_info "Cleaning up SSH connections on remote hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Cleaning up SSH connections on $host..."
        
        # Use sshpass if password is available, otherwise skip remote cleanup
        if [ -n "$SSH_PASSWORD" ] && command -v sshpass >/dev/null 2>&1; then
            sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$host" "
                # Kill any SSH processes that might be stuck
                pkill -f 'ssh.*ControlMaster' 2>/dev/null || true
                pkill -f 'sshd.*notty' 2>/dev/null || true
                # Clean up any socket files
                rm -f /tmp/ssh_mux_* 2>/dev/null || true
            " 2>/dev/null || true
        else
            log_info "Skipping remote cleanup for $host (no stored password available)"
        fi
    done
}

# Function to execute command on remote host with connection reuse
ssh_execute() {
    local host="$1"
    local command="$2"
    local timeout="${3}"
    local silent="${4:-false}"
    local user="${5:-root}"  # Default to root user for Greenplum installation
    
    # Handle empty timeout parameter properly
    if [ -z "$timeout" ]; then
        timeout="$SSH_TIMEOUT"
    fi
    
    local ssh_cmd=$(build_ssh_cmd "$user")
    # Override timeout if specified
    if [ "$timeout" != "$SSH_TIMEOUT" ]; then
        ssh_cmd=$(echo "$ssh_cmd" | sed "s/ConnectTimeout=$SSH_TIMEOUT/ConnectTimeout=$timeout/")
    fi
    
    # Add some debug info (only if not in silent mode)
    if [ "$silent" != "true" ] && [[ "$command" != *"echo 'Connection test successful'"* ]]; then
        local socket_path=$(echo "$SSH_CONTROL_PATH" | sed "s/%h/$host/g" | sed "s/%p/22/g" | sed "s/%r/$user/g")
        if [ -S "$socket_path" ]; then
            # Double-check that the connection is actually working
            if ssh -o ControlPath="$SSH_CONTROL_PATH" -l "$user" -O check "$host" 2>/dev/null; then
                log_info "Using SSH master connection for $host (user: $user)"
            else
                log_warn "SSH master connection socket exists but not working for $host - may prompt for password"
            fi
        else
            log_warn "SSH master connection not available for $host - may prompt for password"
        fi
    fi
    
    $ssh_cmd "$host" "$command"
}

# Function to copy file to remote host with connection reuse
ssh_copy_file() {
    local source_file="$1"
    local host="$2"
    local dest_path="$3"
    local user="${4:-root}"  # Default to root user for Greenplum installation
    
    # Build SCP command with same options as SSH
    local scp_cmd="scp"
    scp_cmd="$scp_cmd -o StrictHostKeyChecking=no"
    scp_cmd="$scp_cmd -o UserKnownHostsFile=/dev/null"
    scp_cmd="$scp_cmd -o ConnectTimeout=$SSH_TIMEOUT"
    scp_cmd="$scp_cmd -o ControlMaster=auto"
    scp_cmd="$scp_cmd -o ControlPath=$SSH_CONTROL_PATH"
    scp_cmd="$scp_cmd -o ControlPersist=$SSH_CONTROL_PERSIST"
    
    $scp_cmd "$source_file" "$user@$host:$dest_path"
}

# Function to generate SSH key for user
generate_ssh_key() {
    local user="$1"
    local key_path="$2"
    local ssh_dir="$(dirname "$key_path")"
    # Ensure home directory exists and is owned by user
    local home_dir="/home/$user"
    if ! sudo -u "$user" test -d "$home_dir"; then
        sudo mkdir -p "$home_dir"
        sudo chown "$user:$user" "$home_dir"
    fi
    # Ensure .ssh directory exists and is owned by user
    if ! sudo -u "$user" test -d "$ssh_dir"; then
        sudo -u "$user" mkdir -p "$ssh_dir"
        sudo chown "$user:$user" "$ssh_dir"
    fi
    # Generate key if it doesn't exist
    if ! sudo -u "$user" test -f "$key_path"; then
        sudo -u "$user" ssh-keygen -t rsa -N "" -f "$key_path" || log_error "Failed to generate SSH key for $user"
    else
        log_info "SSH key already exists for $user"
    fi
}

# Function to setup SSH key authentication
setup_ssh_key_auth() {
    local user="$1"
    local host="$2"
    local password="$3"
    local key_path="$4"
    local pub_key_path="${key_path}.pub"
    log_info "Setting up SSH key authentication for $user@$host..."
    # Generate key if it doesn't exist
    generate_ssh_key "$user" "$key_path"
    # Try ssh-copy-id with explicit public key path
    if ! sshpass -p "$password" ssh-copy-id -i "$pub_key_path" -o StrictHostKeyChecking=no "$user@$host"; then
        log_warn "ssh-copy-id failed, attempting manual public key copy for $user@$host..."
        # Fallback: manually append the public key
        pub_key_content=$(sudo -u "$user" cat "$pub_key_path")
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$user@$host" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key_content' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        if [ $? -eq 0 ]; then
            log_success "Manual public key copy succeeded for $user@$host."
        else
            log_error "Failed to copy SSH key to $host (manual fallback also failed)"
        fi
    fi
}

# Function to setup SSH known hosts
setup_ssh_known_hosts() {
    local user="$1"
    local hosts=("${@:2}")
    local known_hosts_path="/home/$user/.ssh/known_hosts"
    
    log_info "Setting up SSH known hosts for $user..."
    
    # Create .ssh directory if it doesn't exist
    sudo -u "$user" mkdir -p "/home/$user/.ssh"
    sudo -u "$user" touch "$known_hosts_path"
    
    # Add hosts to known_hosts
    for host in "${hosts[@]}"; do
        sudo -u "$user" ssh-keyscan -H "$host" >> "$known_hosts_path" 2>/dev/null || true
    done
    
    # Remove duplicates
    sudo -u "$user" sort -u "$known_hosts_path" -o "$known_hosts_path"
    
    # Set proper permissions
    sudo -u "$user" chmod 600 "$known_hosts_path"
    sudo -u "$user" chmod 700 "/home/$user/.ssh"
}

# Function to setup passwordless SSH for single node
setup_single_node_ssh() {
    local user="$1"
    local key_path="/home/$user/.ssh/id_rsa"
    
    log_info "Setting up SSH for single-node installation..."
    
    # Generate SSH key
    generate_ssh_key "$user" "$key_path"
    
    # Setup localhost access
    local ssh_dir="/home/$user/.ssh"
    local authorized_keys="$ssh_dir/authorized_keys"
    
    # Create authorized_keys if it doesn't exist
    sudo -u "$user" touch "$authorized_keys"
    
    # Add public key to authorized_keys if not already present
    local pub_key_content=$(sudo -u "$user" cat "$key_path.pub")
    if ! sudo -u "$user" grep -q "$pub_key_content" "$authorized_keys" 2>/dev/null; then
        sudo -u "$user" bash -c "echo '$pub_key_content' >> '$authorized_keys'"
    fi
    
    # Set proper permissions
    sudo -u "$user" chmod 600 "$authorized_keys"
    sudo -u "$user" chmod 700 "$ssh_dir"
    
    # Setup known hosts for localhost
    setup_ssh_known_hosts "$user" "localhost" "localhost.localdomain" "$(hostname)"
}

# Function to setup passwordless SSH for multi-node
setup_multi_node_ssh() {
    local user="$1"
    local password="$2"
    local hosts=("${@:3}")
    local key_path="/home/$user/.ssh/id_rsa"
    
    log_info "Setting up SSH for multi-node installation..."
    
    # Generate SSH key on coordinator
    generate_ssh_key "$user" "$key_path"
    
    # Setup SSH authentication to all hosts
    for host in "${hosts[@]}"; do
        setup_ssh_key_auth "$user" "$host" "$password" "$key_path"
    done
    
    # Setup known hosts
    setup_ssh_known_hosts "$user" "${hosts[@]}"
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    local user="$1"
    local host="$2"
    local timeout="${3:-10}"
    
    if sudo -u "$user" ssh -o ConnectTimeout="$timeout" -o BatchMode=yes "$host" "echo 'SSH test successful'" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to cleanup SSH control sockets
cleanup_ssh_sockets() {
    rm -f /tmp/ssh_mux_* 2>/dev/null || true
}

# Function to check if SSH service is running on host
check_ssh_service() {
    local host="$1"
    
    if nc -z -w5 "$host" 22 2>/dev/null; then
        return 0
    else
        return 1
    fi
}