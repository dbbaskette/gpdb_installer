#!/bin/bash

# System library for Greenplum Installer
# Provides system resource checks and OS compatibility functions

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"
source "$(dirname "${BASH_SOURCE[0]}")/ssh.sh"

# Function to check OS compatibility on a host
check_os_compatibility_single() {
    local host="$1"
    
    log_info "Checking OS compatibility on $host..."
    
    local os_release=$(ssh_execute "$host" "cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null" | grep -E '^ID=' | cut -d'=' -f2 | tr -d '"')
    
    if [[ "$os_release" =~ ^(centos|rhel|rocky)$ ]]; then
        local os_version=$(ssh_execute "$host" "cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null" | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1)
        if [[ "$os_version" =~ ^(7|8|9)$ ]]; then
            log_success "OS $os_release $os_version is compatible on $host"
            return 0
        else
            log_error "Incompatible OS version on $host: $os_release $os_version. Only CentOS/RHEL/Rocky Linux 7, 8, or 9 are supported."
        fi
    else
        log_error "Unsupported OS on $host: $os_release. Only CentOS/RHEL/Rocky Linux are supported."
    fi
}

# Function to check OS compatibility on all hosts
check_os_compatibility() {
    local hosts=("$@")
    
    for host in "${hosts[@]}"; do
        check_os_compatibility_single "$host"
    done
}

# Function to check system resources
check_system_resources() {
    local min_memory_gb="${1:-8}"
    local min_disk_gb="${2:-10}"
    
    log_info "Checking system resources..."
    
    # Memory check using /proc/meminfo for Red Hat compatibility
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory=$((total_memory_kb / 1024 / 1024))
    
    if [ "$total_memory" -lt "$min_memory_gb" ]; then
        log_warn "Low memory: ${total_memory}GB available, minimum ${min_memory_gb}GB recommended"
        if ! confirm_continue "Continue with low memory?"; then
            log_error "Installation aborted due to insufficient memory"
        fi
    elif [ "$total_memory" -lt 16 ]; then
        log_warn "Low memory: ${total_memory}GB available, 16GB recommended for production"
    else
        log_success "Memory check passed: ${total_memory}GB available"
    fi
    
    # Disk space check using df with 1K blocks for Red Hat compatibility
    local check_dir="${GPDB_DATA_DIR:-.}"
    local free_space_kb=$(df -k "$check_dir" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
    local free_space=$((free_space_kb / 1024 / 1024))
    
    if [ "$free_space" -lt "$min_disk_gb" ]; then
        log_warn "Low disk space: ${free_space}GB free, minimum ${min_disk_gb}GB recommended"
        if ! confirm_continue "Continue with low disk space?"; then
            log_error "Installation aborted due to insufficient disk space"
        fi
    else
        log_success "Disk space check passed: ${free_space}GB free"
    fi
}

# Function to check dependency on a single host
check_dependency_single() {
    local host="$1"
    local dep="$2"
    
    case "$dep" in
        "sudo")
            if ssh_execute "$host" "command -v sudo" >/dev/null 2>&1 || ssh_execute "$host" "[ -f /usr/bin/sudo ]" >/dev/null 2>&1; then
                return 0
            else
                log_error "Dependency '$dep' not found on $host"
            fi
            ;;
        "sshpass")
            if ssh_execute "$host" "command -v $dep" >/dev/null 2>&1; then
                log_success "sshpass found on $host"
                return 0
            else
                log_warn "sshpass not found on $host. Attempting to install..."
                if install_sshpass "$host"; then
                    log_success "sshpass installed successfully on $host"
                    return 0
                else
                    log_error "Failed to install sshpass on $host"
                fi
            fi
            ;;
        *)
            if ssh_execute "$host" "command -v $dep" >/dev/null 2>&1; then
                return 0
            else
                log_error "Dependency '$dep' not found on $host"
            fi
            ;;
    esac
}

# Function to install sshpass on a host
install_sshpass() {
    local host="$1"
    
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
            echo 'No supported package manager found.'
            exit 1
        fi
    "
    
    if ssh_execute "$host" "$install_script"; then
        return 0
    else
        return 1
    fi
}

# Function to check dependencies on all hosts
check_dependencies() {
    local hosts=("$@")
    local required_dependencies=("sshpass" "sudo")
    
    for host in "${hosts[@]}"; do
        for dep in "${required_dependencies[@]}"; do
            check_dependency_single "$host" "$dep"
        done
    done
}

# Function to check network connectivity between hosts
check_network_connectivity() {
    local hosts=("$@")
    
    log_info "Checking network connectivity between hosts..."
    
    for host in "${hosts[@]}"; do
        if validate_network_connectivity "$host" 3; then
            log_success "Host $host is reachable"
        else
            log_error "Host $host is not reachable"
        fi
        
        # Test SSH connectivity (if not localhost)
        if [[ "$host" != "$(hostname)" ]]; then
            if validate_ssh_connectivity "$host" 10; then
                log_success "SSH to $host works"
            else
                log_warn "SSH to $host may have issues"
            fi
        else
            log_info "Skipping SSH test for localhost"
        fi
    done
}

# Function to check Greenplum version compatibility
check_greenplum_compatibility() {
    local install_files_dir="${1:-files}"
    
    log_info "Checking Greenplum version compatibility..."
    
    local installer_file=$(find "$install_files_dir" -maxdepth 1 -type f -name "greenplum-db-*.el*.x86_64.rpm" 2>/dev/null | head -n1)
    
    if [ -n "$installer_file" ]; then
        local gp_version=$(basename "$installer_file" | sed -n 's/greenplum-db-\([0-9]\+\.[0-9]\+\).*/\1/p')
        local os_version=$(cat /etc/os-release 2>/dev/null | grep -E '^VERSION_ID=' | cut -d'=' -f2 | tr -d '"' | cut -d'.' -f1 || echo "unknown")
        
        log_info "Detected Greenplum version: $gp_version"
        log_info "Detected OS version: $os_version"
        
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

# Function to configure firewall for Greenplum ports
configure_greenplum_firewall() {
    local hosts=("$@")
    
    log_info "Configuring firewall for Greenplum ports on all hosts..."
    
    for host in "${hosts[@]}"; do
        log_info "Configuring firewall on $host..."
        
        local firewall_script="
            # Check if firewalld is running
            if systemctl is-active --quiet firewalld; then
                echo 'Configuring firewalld for Greenplum ports...'
                
                # Allow Greenplum segment ports (40000-40010)
                firewall-cmd --permanent --add-port=40000-40010/tcp
                
                # Allow Greenplum mirror ports (50000-50010)  
                firewall-cmd --permanent --add-port=50000-50010/tcp
                
                # Allow Greenplum replication ports (51000-51010, 52000-52010)
                firewall-cmd --permanent --add-port=51000-51010/tcp
                firewall-cmd --permanent --add-port=52000-52010/tcp
                
                # Allow PostgreSQL coordinator port (5432)
                firewall-cmd --permanent --add-port=5432/tcp
                
                # Reload firewall rules
                firewall-cmd --reload
                
                echo 'Firewall configured for Greenplum'
            else
                echo 'firewalld is not running, skipping firewall configuration'
            fi
        "
        
        if ssh_execute "$host" "sudo bash -c '$firewall_script'"; then
            log_success "Firewall configured on $host"
        else
            log_warn "Failed to configure firewall on $host (continuing anyway)"
        fi
    done
    
    log_success "Firewall configuration completed"
}

# Function to check library versions
check_library_versions() {
    log_info "Checking required library versions..."
    
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

# Helper function to confirm user action
confirm_continue() {
    local message="$1"
    read -p "$message (y/n) [y]: " continue_anyway
    continue_anyway=${continue_anyway:-y}
    if [[ "$continue_anyway" == "y" || "$continue_anyway" == "Y" ]]; then
        return 0
    else
        return 1
    fi
}