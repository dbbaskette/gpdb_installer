#!/bin/bash

# SSH library for Greenplum Installer
# Provides SSH-related operations and connection management

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/validation.sh"

# SSH connection reuse settings
SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"
SSH_CONTROL_PERSIST="5m"

# Function to setup SSH connection multiplexing
setup_ssh_multiplexing() {
    local host="$1"
    ssh -o ControlMaster=auto -o ControlPath="$SSH_CONTROL_PATH" -o ControlPersist="$SSH_CONTROL_PERSIST" -o ConnectTimeout=5 "$host" "echo 'SSH multiplexing setup'" >/dev/null 2>&1
}

# Function to execute command on remote host with connection reuse
ssh_execute() {
    local host="$1"
    local command="$2"
    local timeout="${3:-30}"
    
    ssh -o ControlMaster=auto -o ControlPath="$SSH_CONTROL_PATH" -o ControlPersist="$SSH_CONTROL_PERSIST" -o ConnectTimeout="$timeout" "$host" "$command"
}

# Function to copy file to remote host with connection reuse
ssh_copy_file() {
    local source_file="$1"
    local host="$2"
    local dest_path="$3"
    
    scp -o ControlMaster=auto -o ControlPath="$SSH_CONTROL_PATH" -o ControlPersist="$SSH_CONTROL_PERSIST" "$source_file" "$host:$dest_path"
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