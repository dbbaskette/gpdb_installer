#!/bin/bash

# Validation library for Greenplum Installer
# Provides input validation and system checks

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# Function to validate configuration
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
    
    if [ -z "$GPDB_DATA_ROOT" ]; then
        log_error "Data root directory is not set in configuration."
    fi
    
    log_success "Configuration validation passed."
}

# Function to validate hostname format
validate_hostname() {
    local hostname="$1"
    
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid hostname format: $hostname"
    fi
    
    if [[ ${#hostname} -gt 253 ]]; then
        log_error "Hostname too long: $hostname"
    fi
}

# Function to validate directory path
validate_directory_path() {
    local path="$1"
    local description="$2"
    
    if [[ ! "$path" =~ ^/[a-zA-Z0-9/_.-]*$ ]]; then
        log_error "Invalid $description path format: $path"
    fi
    
    if [[ ${#path} -gt 4096 ]]; then
        log_error "$description path too long: $path"
    fi
}

# Function to validate password strength
validate_password() {
    local password="$1"
    local description="$2"
    
    if [ ${#password} -lt 8 ]; then
        log_warn "$description password is less than 8 characters"
        read -p "Continue anyway? (y/n) [y]: " continue_anyway
        continue_anyway=${continue_anyway:-y}
        if [[ "$continue_anyway" != "y" && "$continue_anyway" != "Y" ]]; then
            log_error "Password validation failed"
        fi
    fi
}

# Function to check if user has sudo privileges
check_sudo_privileges() {
    log_info "Checking sudo privileges..."
    if ! sudo -n true 2>/dev/null; then
        log_error "This script requires sudo privileges. Please run as a user with sudo access."
    fi
    log_success "Sudo privileges confirmed."
}

# Function to validate network connectivity
validate_network_connectivity() {
    local host="$1"
    local timeout="${2:-10}"
    
    if ! ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to validate SSH connectivity
validate_ssh_connectivity() {
    local host="$1"
    local timeout="${2:-10}"
    
    if ! ssh -o ConnectTimeout="$timeout" -o BatchMode=yes "$host" "echo 'SSH test'" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Function to validate file existence and permissions
validate_file_access() {
    local file_path="$1"
    local required_perms="$2"  # r, w, x combination
    
    if [ ! -f "$file_path" ]; then
        log_error "File not found: $file_path"
    fi
    
    if [[ "$required_perms" =~ r ]] && [ ! -r "$file_path" ]; then
        log_error "File not readable: $file_path"
    fi
    
    if [[ "$required_perms" =~ w ]] && [ ! -w "$file_path" ]; then
        log_error "File not writable: $file_path"
    fi
    
    if [[ "$required_perms" =~ x ]] && [ ! -x "$file_path" ]; then
        log_error "File not executable: $file_path"
    fi
}

# Function to validate system requirements
validate_system_requirements() {
    local min_memory_gb="${1:-8}"
    local min_disk_gb="${2:-10}"
    
    # Memory check
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory=$((total_memory_kb / 1024 / 1024))
    
    if [ "$total_memory" -lt "$min_memory_gb" ]; then
        log_warn "Insufficient memory: ${total_memory}GB available, minimum ${min_memory_gb}GB required"
        return 1
    fi
    
    # Disk space check
    local check_dir="${GPDB_DATA_ROOT:-.}"
    local free_space_kb=$(df -k "$check_dir" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    local free_space=$((free_space_kb / 1024 / 1024))
    
    if [ "$free_space" -lt "$min_disk_gb" ]; then
        log_warn "Insufficient disk space: ${free_space}GB free, minimum ${min_disk_gb}GB required"
        return 1
    fi
    
    return 0
}