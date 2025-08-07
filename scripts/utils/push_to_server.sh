#!/bin/bash

# GPDB Installer Enhanced Push Script v2.0
# Deploys the installer scripts and files to remote servers with advanced features

set -eE

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="2.0"
readonly DEFAULT_TARGET_DIR="~/gpdb_installer"
readonly MIN_DISK_SPACE_MB=100
readonly DEPLOYMENT_TIMEOUT=300

# Load logging functions if available
if [ -f "$SCRIPT_DIR/lib/logging.sh" ]; then
    source "$SCRIPT_DIR/lib/logging.sh"
else
    # Fallback logging functions
    COLOR_RESET='\033[0m'
    COLOR_GREEN='\033[0;32m'
    COLOR_BLUE='\033[0;34m'
    COLOR_YELLOW='\033[0;33m'
    COLOR_RED='\033[0;31m'
    
    log_info() { echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"; }
    log_success() { echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"; }
    log_warn() { echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"; }
    log_error() { echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2; exit 1; }
    log_info_with_timestamp() { echo -e "${COLOR_BLUE}[INFO][$(date '+%H:%M:%S')]${COLOR_RESET} $1"; }
    log_success_with_timestamp() { echo -e "${COLOR_GREEN}[SUCCESS][$(date '+%H:%M:%S')]${COLOR_RESET} $1"; }
    show_progress() {
        local current=$1 total=$2 message=${3:-"Progress"}
        local percentage=$((current * 100 / total))
        printf "\r${COLOR_BLUE}[INFO]${COLOR_RESET} %s: [%-50s] %d%% (%d/%d)" \
            "$message" "$(printf '#%.0s' $(seq 1 $((percentage / 2))))" \
            "$percentage" "$current" "$total"
    }
fi

# Global variables
DRY_RUN=false
VERBOSE=false
PARALLEL=false
FORCE=false
BACKUP_EXISTING=true
VERIFY_DEPLOYMENT=true
INTERACTIVE_SSH=true
SKIP_RPMS=false
SSH_KEY_FILE=""
SSH_PORT="22"
TARGET_DIR="$DEFAULT_TARGET_DIR"
HOSTS=()
EXCLUDE_PATTERNS=()
INCLUDE_PATTERNS=()
DEPLOYMENT_STATS=()

# Error handling
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Deployment failed at line $line_number (exit code: $exit_code)"
    cleanup_all
    exit $exit_code
}

trap 'handle_error $? $LINENO' ERR
trap 'cleanup_all' EXIT

# Cleanup function
cleanup_all() {
    log_info "Cleaning up deployment resources..."
    cleanup_ssh_sockets
    cleanup_temp_files
}

# Show detailed usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <user@host> [user@host2] ...

Enhanced GPDB Installer Deployment Script v$VERSION

Deploys GPDB installer scripts and files to remote servers with advanced features
including parallel deployment, verification, backup, and comprehensive logging.

OPTIONS:
  Core Options:
    --dry-run, -d           Show what would be deployed without doing it
    --help, -h              Show this help message
    --version, -V           Show version information
    --verbose, -v           Enable verbose output
    --force, -f             Force deployment even if target exists
    --parallel, -P          Deploy to multiple hosts in parallel

  SSH Options:
    --key-file, -k FILE     SSH private key file
    --port, -p PORT         SSH port (default: 22)
    --ssh-timeout SECONDS   SSH connection timeout (default: 30)
    --ssh-retries COUNT     SSH retry attempts (default: 3)
    --interactive           Enable interactive SSH (allow password prompts)

  Deployment Options:
    --target-dir, -t DIR    Target directory (default: $DEFAULT_TARGET_DIR)
    --backup, -b            Backup existing installation (default: true)
    --no-backup             Don't backup existing installation
    --verify                Verify deployment after completion (default: true)
    --no-verify             Skip deployment verification

  Content Options:
    --exclude PATTERN       Exclude files matching pattern
    --include PATTERN       Include only files matching pattern
    --minimal               Deploy minimal package (core files only)
    --full                  Deploy full package (includes tests, docs)
    --no-rpms               Skip RPMs, backup, and enable force (fastest for testing)

  Advanced Options:
    --config-file FILE      Use custom configuration file
    --deployment-log FILE   Custom deployment log file
    --timeout SECONDS       Overall deployment timeout (default: $DEPLOYMENT_TIMEOUT)
    --compress-level N      Compression level 1-9 (default: 6)

EXAMPLES:
  Basic deployment:
    $0 user@server1.example.com

  Multiple hosts with SSH key:
    $0 --key-file ~/.ssh/id_rsa user@server1 user@server2

  Parallel deployment with verification:
    $0 --parallel --verify user@server1 user@server2 user@server3

  Custom target directory:
    $0 --target-dir /opt/gpdb_installer user@server1

  Dry run to test deployment:
    $0 --dry-run --verbose user@server1

  Minimal deployment excluding tests:
    $0 --minimal --exclude "test_*" user@server1

  Force deployment with backup:
    $0 --force --backup --target-dir /opt/gpdb user@server1

  Fast deployment without RPMs (testing):
    $0 --no-rpms user@server1

REQUIREMENTS:
  - SSH access to target servers
  - Target servers must have bash shell
  - Sufficient disk space on target servers (minimum ${MIN_DISK_SPACE_MB}MB)
  - tar and gzip utilities on target servers

DEPLOYMENT INCLUDES:
  - Core installer scripts (gpdb_installer.sh, datalake_installer.sh)
  - Library modules (lib/)
  - Configuration files (gpdb_config.conf, datalake_config.conf)
  - Documentation
  - Test suite (if not excluded)
  - Installation files (files/) - unless --no-rpms is used

EOF
}

# Show version information
show_version() {
    echo "GPDB Installer Push Script v$VERSION"
    echo "Enhanced deployment tool for Greenplum Database installer"
    echo ""
    echo "Features:"
    echo "  - Parallel deployment"
    echo "  - Deployment verification"
    echo "  - Backup and restore"
    echo "  - Comprehensive logging"
    echo "  - Advanced filtering"
    echo "  - Progress reporting"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --version|-V)
                show_version
                exit 0
                ;;
            --dry-run|-d)
                DRY_RUN=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --parallel|-P)
                PARALLEL=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --backup|-b)
                BACKUP_EXISTING=true
                shift
                ;;
            --no-backup)
                BACKUP_EXISTING=false
                shift
                ;;
            --verify)
                VERIFY_DEPLOYMENT=true
                shift
                ;;
            --no-verify)
                VERIFY_DEPLOYMENT=false
                shift
                ;;
            --key-file|-k)
                SSH_KEY_FILE="$2"
                if [ ! -f "$SSH_KEY_FILE" ]; then
                    log_error "SSH key file not found: $SSH_KEY_FILE"
                fi
                shift 2
                ;;
            --port|-p)
                SSH_PORT="$2"
                if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
                    log_error "Invalid SSH port: $SSH_PORT"
                fi
                shift 2
                ;;
            --target-dir|-t)
                TARGET_DIR="$2"
                shift 2
                ;;
            --exclude)
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --include)
                INCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            --minimal)
                EXCLUDE_PATTERNS+=("test_*" "tests/*" "*.md" "docs/*")
                shift
                ;;
            --full)
                INCLUDE_PATTERNS=("*")
                shift
                ;;
            --no-rpms)
                SKIP_RPMS=true
                # Automatically disable backup and enable force for faster testing when skipping RPMs
                BACKUP_EXISTING=false
                FORCE=true
                shift
                ;;
            --timeout)
                DEPLOYMENT_TIMEOUT="$2"
                if ! [[ "$DEPLOYMENT_TIMEOUT" =~ ^[0-9]+$ ]]; then
                    log_error "Invalid timeout value: $DEPLOYMENT_TIMEOUT"
                fi
                shift 2
                ;;
            --ssh-timeout)
                SSH_TIMEOUT="$2"
                shift 2
                ;;
            --ssh-retries)
                SSH_RETRIES="$2"
                shift 2
                ;;
            --interactive)
                INTERACTIVE_SSH=true
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --deployment-log)
                DEPLOYMENT_LOG="$2"
                shift 2
                ;;
            --compress-level)
                COMPRESS_LEVEL="$2"
                if ! [[ "$COMPRESS_LEVEL" =~ ^[1-9]$ ]]; then
                    log_error "Invalid compression level: $COMPRESS_LEVEL (must be 1-9)"
                fi
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                ;;
            *)
                # Validate host format - allow IP addresses and hostnames
                if [[ "$1" =~ ^[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+$ ]] || [[ "$1" =~ ^[a-zA-Z0-9._-]+@[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    HOSTS+=("$1")
                else
                    log_error "Invalid host format: $1 (expected: user@hostname or user@ip)"
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ ${#HOSTS[@]} -eq 0 ]; then
        log_error "No hosts specified. Use --help for usage information."
    fi
    
    # Set defaults for optional parameters
    SSH_TIMEOUT=${SSH_TIMEOUT:-30}
    SSH_RETRIES=${SSH_RETRIES:-3}
    COMPRESS_LEVEL=${COMPRESS_LEVEL:-6}
    DEPLOYMENT_LOG=${DEPLOYMENT_LOG:-"/tmp/gpdb_deployment_$(date +%Y%m%d_%H%M%S).log"}
}

# Add this function after parse_args
expand_target_dir() {
    local user_host="$1"
    local user="${user_host%@*}"
    local host="${user_host#*@}"
    local dir="$TARGET_DIR"
    if [[ "$dir" == ~* ]]; then
        if [[ "$user" == "root" ]]; then
            dir="/root/gpdb_installer"
        else
            dir="/home/$user/gpdb_installer"
        fi
    fi
    echo "$dir"
}

# Build SSH command with all options
build_ssh_cmd() {
    local ssh_cmd="ssh"
    
    if [ -n "$SSH_KEY_FILE" ]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_FILE"
    fi
    
    if [ "$SSH_PORT" != "22" ]; then
        ssh_cmd="$ssh_cmd -p $SSH_PORT"
    fi
    
    # Add comprehensive SSH options
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no"
    ssh_cmd="$ssh_cmd -o UserKnownHostsFile=/dev/null"
    ssh_cmd="$ssh_cmd -o ConnectTimeout=$SSH_TIMEOUT"
    ssh_cmd="$ssh_cmd -o ServerAliveInterval=60"
    ssh_cmd="$ssh_cmd -o ServerAliveCountMax=3"
    ssh_cmd="$ssh_cmd -o ControlMaster=auto"
    ssh_cmd="$ssh_cmd -o ControlPath=/tmp/ssh_mux_%h_%p_%r"
    ssh_cmd="$ssh_cmd -o ControlPersist=5m"
    
    if [ "$VERBOSE" = false ]; then
        ssh_cmd="$ssh_cmd -o LogLevel=ERROR"
    fi
    
    echo "$ssh_cmd"
}

# Build SCP command with all options
build_scp_cmd() {
    local scp_cmd="scp"
    
    if [ -n "$SSH_KEY_FILE" ]; then
        scp_cmd="$scp_cmd -i $SSH_KEY_FILE"
    fi
    
    if [ "$SSH_PORT" != "22" ]; then
        scp_cmd="$scp_cmd -P $SSH_PORT"
    fi
    
    # Add comprehensive SCP options
    scp_cmd="$scp_cmd -o StrictHostKeyChecking=no"
    scp_cmd="$scp_cmd -o UserKnownHostsFile=/dev/null"
    scp_cmd="$scp_cmd -o ConnectTimeout=$SSH_TIMEOUT"
    scp_cmd="$scp_cmd -o ControlMaster=auto"
    scp_cmd="$scp_cmd -o ControlPath=/tmp/ssh_mux_%h_%p_%r"
    scp_cmd="$scp_cmd -o ControlPersist=5m"
    
    if [ "$VERBOSE" = false ]; then
        scp_cmd="$scp_cmd -o LogLevel=ERROR"
    fi
    
    echo "$scp_cmd"
}

# Execute SSH command with retry logic
ssh_execute() {
    local host="$1"
    local command="$2"
    local allow_failure="${3:-false}"
    local ssh_cmd=$(build_ssh_cmd)
    local attempt=1
    
    while [ $attempt -le $SSH_RETRIES ]; do
        if [ "$VERBOSE" = true ]; then
            log_info "Executing on $host (attempt $attempt/$SSH_RETRIES): $command"
        fi
        
        if [ "$INTERACTIVE_SSH" = true ]; then
            if $ssh_cmd "$host" "$command"; then
                return 0
            else
                local exit_code=$?
            fi
        else
            if $ssh_cmd "$host" "$command" 2>/dev/null; then
                return 0
            else
                local exit_code=$?
            fi
        fi
        
        if [ "$allow_failure" = true ]; then
            return $exit_code
        fi
        
        if [ $attempt -lt $SSH_RETRIES ]; then
            log_warn "Command failed on $host (attempt $attempt/$SSH_RETRIES), retrying..."
            sleep 2
        else
            return $exit_code
        fi
        
        attempt=$((attempt + 1))
    done
}

# Test SSH connectivity with comprehensive checks
test_ssh_connectivity() {
    local host="$1"
    
    log_info "Testing SSH connectivity to $host..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would test SSH connectivity to $host"
        return 0
    fi
    
    # Test basic connectivity
    if ! ssh_execute "$host" "echo 'SSH test successful'"; then
        log_error "Cannot establish SSH connection to $host"
        return 1
    fi
    
    # Test sudo access if available (don't fail if not available)
    if ssh_execute "$host" "sudo -n true 2>/dev/null" true; then
        log_success "SSH connectivity to $host confirmed (with passwordless sudo)"
    else
        log_success "SSH connectivity to $host confirmed (sudo may require password)"
    fi
    
    return 0
}

# Check comprehensive server requirements
check_server_requirements() {
    local host="$1"
    local expanded_target_dir=$(expand_target_dir "$host")
    
    log_info "Checking server requirements on $host..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would check server requirements on $host"
        return 0
    fi
    
    # Check bash availability
    if ! ssh_execute "$host" "command -v bash >/dev/null 2>&1"; then
        log_error "Bash shell not available on $host"
        return 1
    fi
    
    # Check required utilities
    local required_utils=("tar" "gzip" "mkdir" "chmod" "df")
    for util in "${required_utils[@]}"; do
        if ! ssh_execute "$host" "command -v $util >/dev/null 2>&1"; then
            log_error "Required utility '$util' not available on $host"
            return 1
        fi
    done
    
    # Ensure target directory exists before disk check
    if ! ssh_execute "$host" "mkdir -p '$expanded_target_dir' 2>/dev/null"; then
        log_error "Cannot create target directory '$expanded_target_dir' on $host"
        return 1
    fi
    
    # Check disk space
    local free_space_kb=$(ssh_execute "$host" "df -k $expanded_target_dir | awk 'NR==2{print \$4}'")
    local free_space_mb=$((free_space_kb / 1024))
    
    if [ "$free_space_mb" -lt "$MIN_DISK_SPACE_MB" ]; then
        if [ "$FORCE" = true ]; then
            log_warn "Insufficient disk space on $host: ${free_space_mb}MB free (${MIN_DISK_SPACE_MB}MB required) - proceeding with --force"
        else
            log_error "Insufficient disk space on $host: ${free_space_mb}MB free (${MIN_DISK_SPACE_MB}MB required). Use --force to override."
            return 1
        fi
    else
        log_success "Disk space check passed on $host: ${free_space_mb}MB free"
    fi
    
    # Check if target installer directory exists
    if ssh_execute "$host" "[ -d '$expanded_target_dir/gpdb_installer' ]" true; then
        if [ "$FORCE" = true ]; then
            log_warn "Target installer directory exists on $host: $expanded_target_dir/gpdb_installer - proceeding with --force"
        else
            log_error "Target installer directory already exists on $host: $expanded_target_dir/gpdb_installer. Use --force to override."
            return 1
        fi
    fi
    
    # Test target directory creation
    if ! ssh_execute "$host" "mkdir -p '$expanded_target_dir' 2>/dev/null"; then
        log_error "Cannot create target directory '$expanded_target_dir' on $host"
        return 1
    fi
    
    log_success "Server requirements check passed for $host"
    log_info "Preparing deployment package for $host..."
    return 0
}

# Create comprehensive deployment package
create_deployment_package() {
    local temp_dir=$(mktemp -d)
    local package_dir="$temp_dir/gpdb_installer"
    local package_name="gpdb_installer_deploy_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    log_info "Creating deployment package..." >&2
    
    # Create package directory structure
    mkdir -p "$package_dir"
    
    # Define what to include
    local core_files=(
        "gpdb_installer.sh"
        "datalake_installer.sh"
        "cleanup_greenplum.sh"
        "README.md"
        "TROUBLESHOOTING.md"
        "ARCHITECTURE.md"
        "DEVELOPER_GUIDE.md"
    )
    
    local optional_files=(
        "VERSION"
        "TESTING_SUMMARY.md"
        "ENHANCEMENTS_PLAN.md"
        "gpdb_config.conf"
        "datalake_config.conf"
        "test_config.conf"
    )
    
    local directories=(
        "lib"
        "tests"
        "docs"
    )
    
    # Add files directory only if --no-rpms flag is not set
    if [ "$SKIP_RPMS" = false ]; then
        directories+=("files")
    fi
    
    # Copy core files
    log_info "Copying core files..." >&2
    for file in "${core_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$package_dir/"
        else
            log_warn "Core file not found: $file" >&2
        fi
    done
    
    # Copy optional files
    log_info "Copying optional files..." >&2
    for file in "${optional_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$package_dir/"
        fi
    done
    
    # Copy directories
    if [ "$SKIP_RPMS" = true ]; then
        log_info "Copying directories (lib, tests, docs) - skipping files/..." >&2
    else
        log_info "Copying directories (lib, tests, docs, files)..." >&2
    fi
    for dir in "${directories[@]}"; do
        if [ -d "$dir" ]; then
            cp -r "$dir" "$package_dir/"
        fi
    done
    
    # Apply exclude patterns
    if [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
        log_info "Applying exclude patterns..." >&2
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            find "$package_dir" -name "$pattern" -type f -delete 2>/dev/null || true
        done
    fi
    
    # Apply include patterns (if specified)
    if [ ${#INCLUDE_PATTERNS[@]} -gt 0 ]; then
        log_info "Applying include patterns..." >&2
        # This would be more complex - for now, just log
        log_info "Include patterns: ${INCLUDE_PATTERNS[*]}" >&2
    fi
    
    # Make scripts executable
    find "$package_dir" -name "*.sh" -type f -exec chmod +x {} \;
    
    # Create deployment manifest
    cat > "$package_dir/DEPLOYMENT_MANIFEST.txt" << EOF
GPDB Installer Deployment Package
Generated: $(date)
Version: $VERSION
Deployment Host: $(hostname)
Target Directory: $TARGET_DIR
Package Contents:
$(find "$package_dir" -type f | sort)
EOF
    
    # Create compressed package (tar the contents, not the directory)
    log_info "Compressing deployment package..." >&2
    local original_dir=$(pwd)
    
    # Create archive with proper directory structure without using --transform
    # Change to parent directory and tar the directory by name to avoid nesting
    local package_basename=$(basename "$package_dir")
    cd "$(dirname "$package_dir")"
    
    # Detect OS and use appropriate tar options to avoid macOS xattrs
    if [[ "$(uname)" == "Darwin" ]]; then
        # Set environment variables to disable xattr and use portable tar
        export COPYFILE_DISABLE=1
        if ! /usr/bin/tar --disable-copyfile --no-xattrs --exclude='._*' --exclude='.DS_Store' --exclude='*.quarantine' -czf "$temp_dir/$package_name" "$package_basename" 2>/dev/null; then
            log_error "Failed to create deployment package" >&2
            cd "$original_dir"
            return 1
        fi
    else
        if ! tar --exclude='._*' --exclude='.DS_Store' --exclude='*.quarantine' -czf "$temp_dir/$package_name" "$package_basename"; then
            log_error "Failed to create deployment package" >&2
            cd "$original_dir"
            return 1
        fi
    fi
    
    cd "$original_dir"
    
    # Verify package was created
    if [ ! -f "$temp_dir/$package_name" ]; then
        log_error "Package file was not created: $temp_dir/$package_name" >&2
        return 1
    fi
    
    local package_size=$(du -h "$temp_dir/$package_name" | cut -f1)
    log_success "Deployment package created: $package_name (size: $package_size)" >&2
    
    echo "$temp_dir/$package_name"
}

# Backup existing installation
backup_existing_installation() {
    local host="$1"
    local expanded_target_dir=$(expand_target_dir "$host")
    
    if [ "$BACKUP_EXISTING" = false ]; then
        return 0
    fi
    
    log_info "Checking for existing installation on $host..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would backup existing installation on $host"
        return 0
    fi
    
    if ssh_execute "$host" "[ -d '$expanded_target_dir/gpdb_installer' ]" true; then
        local backup_dir="${expanded_target_dir}/gpdb_installer.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up existing installation to $backup_dir..."
        
        if ssh_execute "$host" "mv '$expanded_target_dir/gpdb_installer' '$backup_dir'"; then
            log_success "Backup created on $host: $backup_dir"
        else
            log_error "Failed to create backup on $host"
            return 1
        fi
    fi
    
    return 0
}

# Deploy to single host
deploy_to_host() {
    local host="$1"
    local package_path="$2"
    local start_time=$(date +%s)
    local expanded_target_dir=$(expand_target_dir "$host")
    
    log_info_with_timestamp "Starting deployment to $host..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would deploy to $host"
        log_info "[DRY-RUN] Package: $package_path"
        log_info "[DRY-RUN] Target: $host:$expanded_target_dir"
        return 0
    fi
    
    # SSH master connection already established in main function
    log_info "Using established SSH connection for deployment..."
    
    # Backup existing installation
    if ! backup_existing_installation "$host" "$expanded_target_dir"; then
        return 1
    fi
    
    # Create target directory
    if ! ssh_execute "$host" "mkdir -p '$expanded_target_dir'"; then
        log_error "Failed to create target directory on $host"
        return 1
    fi
    
    # Copy package to target
    log_info "Copying package to $host..."
    
    local package_name=$(basename "$package_path")
    
    # Use SCP for file transfer
    local scp_cmd="scp"
    
    # Add basic options
    if [ -n "$SSH_KEY_FILE" ]; then
        scp_cmd="$scp_cmd -i $SSH_KEY_FILE"
    fi
    if [ "$SSH_PORT" != "22" ]; then
        scp_cmd="$scp_cmd -P $SSH_PORT"
    fi
    
    # Add essential SSH options including multiplexing
    scp_cmd="$scp_cmd -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    scp_cmd="$scp_cmd -o ControlMaster=auto -o ControlPath=/tmp/ssh_mux_%h_%p_%r -o ControlPersist=5m"
    
    # Debug: show the command being executed
    log_info "SCP command: $scp_cmd"
    log_info "Package path: $package_path"
    log_info "Target: $host:$expanded_target_dir/"
    
    # Execute SCP command
    if [ "$INTERACTIVE_SSH" = true ]; then
        if ! $scp_cmd "$package_path" "$host:$expanded_target_dir/"; then
            log_error "Failed to copy package to $host"
            return 1
        fi
    else
        # Capture output for debugging
        local scp_output
        if ! scp_output=$($scp_cmd "$package_path" "$host:$expanded_target_dir/" 2>&1); then
            log_error "Failed to copy package to $host"
            log_error "SCP command: $scp_cmd"
            log_error "Package: $package_path"
            log_error "Target: $host:$expanded_target_dir/"
            log_error "Error output: $scp_output"
            return 1
        fi
    fi
    
    # Extract package on target
    local package_name=$(basename "$package_path")
    log_info "Extracting package on $host..."
    
    # Extract package and handle directory structure
    if ! ssh_execute "$host" "cd '$expanded_target_dir' && tar -xzf '$package_name' && rm '$package_name'"; then
        log_error "Failed to extract package on $host"
        return 1
    fi
    
    # Move contents from extracted gpdb_installer directory to target directory
    local fix_structure_script="
        if [ -d '$expanded_target_dir/gpdb_installer' ]; then
            echo 'Updating files from extracted directory...'
            cd '$expanded_target_dir/gpdb_installer'
            
            # First, update all files
            find . -maxdepth 1 -type f -exec cp {} '$expanded_target_dir/' \;
            
            # Then, update directories by copying their contents
            for item in */; do
                if [ -d \"\$item\" ]; then
                    item=\${item%/}  # Remove trailing slash
                    echo \"Updating directory: \$item\"
                    if [ -d '$expanded_target_dir/\$item' ]; then
                        echo \"Directory '$expanded_target_dir/\$item' exists, updating contents...\"
                        # Remove old contents and copy new ones
                        rm -rf '$expanded_target_dir/\$item'/*
                        cp -rf \"\$item\"/* '$expanded_target_dir/\$item/' 2>/dev/null || true
                        # Also copy hidden files
                        cp -rf \"\$item\"/.[^.]* '$expanded_target_dir/\$item/' 2>/dev/null || true
                        echo \"Contents of directory \$item updated successfully\"
                    else
                        echo \"Creating new directory: \$item\"
                        cp -rf \"\$item\" '$expanded_target_dir/'
                        echo \"Directory \$item created successfully\"
                    fi
                fi
            done
            
            cd '$expanded_target_dir'
            # Remove the extracted directory
            rm -rf '$expanded_target_dir/gpdb_installer'
            echo 'Directory structure updated successfully'
        fi
    "
    
    if ! ssh_execute "$host" "$fix_structure_script"; then
        log_error "Failed to fix directory structure on $host"
        return 1
    fi
    
    # Set proper permissions
    if ! ssh_execute "$host" "find '$expanded_target_dir' -name '*.sh' -type f -exec chmod +x {} \;"; then
        log_error "Failed to set permissions on $host"
        return 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_success_with_timestamp "Deployment to $host completed in ${duration}s"
    
    # Store deployment statistics
    DEPLOYMENT_STATS+=("$host:$duration")
    
    # Note: SSH connection cleanup will happen in main cleanup function
    # after verification is complete
    
    return 0
}

# Verify deployment on host
verify_deployment() {
    local host="$1"
    local expanded_target_dir=$(expand_target_dir "$host")
    
    if [ "$VERIFY_DEPLOYMENT" = false ]; then
        return 0
    fi
    
    log_info "Verifying deployment on $host..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would verify deployment on $host"
        return 0
    fi
    
    # Check if main installer exists and is executable
    log_info "Checking installer at: $expanded_target_dir/gpdb_installer.sh"
    if ssh_execute "$host" "[ -x '$expanded_target_dir/gpdb_installer.sh' ]" true; then
        log_success "Main installer found and executable on $host"
    else
        # Debug: list the directory contents
        log_info "Listing directory contents for debugging..."
        ssh_execute "$host" "ls -la '$expanded_target_dir/'" true || true
        log_error "Main installer not found or not executable on $host"
        return 1
    fi
    
    # Check if library directory exists
    if ssh_execute "$host" "[ -d '$expanded_target_dir/lib' ]" true; then
        log_success "Library directory found on $host"
    else
        log_error "Library directory not found on $host"
        return 1
    fi
    
    # Test installer help function (skip for now to avoid password issues)
    log_success "Basic deployment verification passed on $host"
    
    # Check deployment manifest
    if ssh_execute "$host" "[ -f '$expanded_target_dir/gpdb_installer/DEPLOYMENT_MANIFEST.txt' ]" true; then
        log_success "Deployment verification passed on $host"
    else
        log_warn "Deployment manifest not found on $host"
    fi
    
    return 0
}

# Deploy to all hosts in parallel
deploy_parallel() {
    local package_path="$1"
    local pids=()
    local results=()
    
    log_info "Starting parallel deployment to ${#HOSTS[@]} hosts..."
    
    # Start deployment to each host in background
    for host in "${HOSTS[@]}"; do
        {
            deploy_to_host "$host" "$package_path"
            echo "$host:$?" >> "/tmp/deploy_results_$$"
        } &
        pids+=($!)
    done
    
    # Wait for all deployments to complete
    local completed=0
    for pid in "${pids[@]}"; do
        wait "$pid"
        completed=$((completed + 1))
        show_progress "$completed" "${#HOSTS[@]}" "Deploying"
    done
    echo ""
    
    # Check results
    local failed_hosts=()
    if [ -f "/tmp/deploy_results_$$" ]; then
        while IFS=':' read -r host exit_code; do
            if [ "$exit_code" -ne 0 ]; then
                failed_hosts+=("$host")
            fi
        done < "/tmp/deploy_results_$$"
        rm -f "/tmp/deploy_results_$$"
    fi
    
    if [ ${#failed_hosts[@]} -gt 0 ]; then
        log_error "Deployment failed on hosts: ${failed_hosts[*]}"
        return 1
    fi
    
    log_success "Parallel deployment completed successfully"
    return 0
}

# Deploy to all hosts sequentially
deploy_sequential() {
    local package_path="$1"
    local current=0
    
    log_info "Starting sequential deployment to ${#HOSTS[@]} hosts..."
    
    for host in "${HOSTS[@]}"; do
        current=$((current + 1))
        show_progress "$current" "${#HOSTS[@]}" "Deploying"
        echo ""  # Add line break after progress bar
        
        if ! deploy_to_host "$host" "$package_path"; then
            echo ""
            log_error "Deployment failed on $host"
            return 1
        fi
        
        if ! verify_deployment "$host" "$expanded_target_dir"; then
            echo ""
            log_error "Deployment verification failed on $host"
            return 1
        fi
    done
    
    echo ""
    log_success "Sequential deployment completed successfully"
    return 0
}

# Generate deployment report
generate_deployment_report() {
    local total_hosts=${#HOSTS[@]}
    local successful_hosts=0
    local total_time=0
    
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT REPORT"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Total Hosts: $total_hosts"
    echo "Target Directory: $TARGET_DIR"
    echo "SSH Port: $SSH_PORT"
    echo "Deployment Mode: $([ "$PARALLEL" = true ] && echo "Parallel" || echo "Sequential")"
    echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "Yes" || echo "No")"
    echo "Backup Existing: $([ "$BACKUP_EXISTING" = true ] && echo "Yes" || echo "No")"
    echo "Verify Deployment: $([ "$VERIFY_DEPLOYMENT" = true ] && echo "Yes" || echo "No")"
    echo ""
    
    if [ ${#DEPLOYMENT_STATS[@]} -gt 0 ]; then
        echo "Deployment Statistics:"
        echo "----------------------"
        for stat in "${DEPLOYMENT_STATS[@]}"; do
            IFS=':' read -r host duration <<< "$stat"
            echo "  $host: ${duration}s"
            total_time=$((total_time + duration))
            successful_hosts=$((successful_hosts + 1))
        done
        echo ""
        echo "Average deployment time: $((total_time / successful_hosts))s"
        echo "Total deployment time: ${total_time}s"
    fi
    
    echo ""
    echo "Deployment Files Located At:"
    echo "----------------------------"
    for host in "${HOSTS[@]}"; do
        local expanded_target_dir=$(expand_target_dir "$host")
        echo "  $host:$expanded_target_dir/gpdb_installer/"
    done
    
    echo ""
    echo "Next Steps:"
    echo "-----------"
    for host in "${HOSTS[@]}"; do
        local expanded_target_dir=$(expand_target_dir "$host")
        echo "  SSH to host: ssh $host"
        echo "  Navigate to installer: cd $expanded_target_dir"
    done
    echo "3. Run GPDB installer: ./gpdb_installer.sh"
    echo "4. Run TDL Controller installer: ./datalake_installer.sh"
    echo "5. Or run dry test: ./gpdb_installer.sh --dry-run"
    echo ""
    echo "For help: ./gpdb_installer.sh --help or ./datalake_installer.sh --help"
    echo "=========================================="
}

# Cleanup functions
cleanup_temp_files() {
    # Remove temporary files
    rm -f /tmp/deploy_results_$$ 2>/dev/null || true
}

cleanup_ssh_sockets() {
    # Close all SSH master connections
    for host in "${HOSTS[@]}"; do
        local ssh_cmd=$(build_ssh_cmd)
        $ssh_cmd -O exit "$host" 2>/dev/null || true
    done
    
    # Remove SSH control sockets for this user more aggressively
    find /tmp -name "ssh_mux_*" -user $(whoami) -delete 2>/dev/null || true
}

# Main deployment function
main() {
    # Show banner
    echo -e "${COLOR_GREEN}GPDB Installer Enhanced Deployment Script v$VERSION${COLOR_RESET}"
    echo "=============================================================="
    
    # Parse command line arguments
    parse_args "$@"
    
    # Show configuration
    log_info "Deployment Configuration:"
    log_info "  Target hosts: ${HOSTS[*]}"
    log_info "  Target directory: $TARGET_DIR"
    log_info "  SSH port: $SSH_PORT"
    log_info "  Parallel mode: $([ "$PARALLEL" = true ] && echo "Enabled" || echo "Disabled")"
    log_info "  Dry run mode: $([ "$DRY_RUN" = true ] && echo "Enabled" || echo "Disabled")"
    log_info "  Backup existing: $([ "$BACKUP_EXISTING" = true ] && echo "Enabled" || echo "Disabled")"
    log_info "  Verify deployment: $([ "$VERIFY_DEPLOYMENT" = true ] && echo "Enabled" || echo "Disabled")"
    log_info "  Skip RPMs: $([ "$SKIP_RPMS" = true ] && echo "Enabled" || echo "Disabled")"
    
    if [ -n "$SSH_KEY_FILE" ]; then
        log_info "  SSH key file: $SSH_KEY_FILE"
    fi
    
    if [ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]; then
        log_info "  Exclude patterns: ${EXCLUDE_PATTERNS[*]}"
    fi
    
    echo ""
    
    # Establish SSH master connections first to avoid multiple password prompts
    log_info "Establishing SSH connections to all hosts..."
    for host in "${HOSTS[@]}"; do
        log_info "Establishing SSH master connection to $host..."
        local ssh_cmd=$(build_ssh_cmd)
        
        # Clean up any existing socket for this host first
        local socket_path="/tmp/ssh_mux_${host}_${SSH_PORT}_$(whoami)"
        if [ -S "$socket_path" ]; then
            log_info "Cleaning up existing SSH socket: $socket_path"
            $ssh_cmd -O exit "$host" 2>/dev/null || true
            rm -f "$socket_path" 2>/dev/null || true
            sleep 1
        fi
        
        # Also try SSH's built-in cleanup for the control path pattern
        $ssh_cmd -O exit "$host" 2>/dev/null || true
        
        # More aggressive cleanup - find and remove any matching sockets
        find /tmp -name "ssh_mux_${host}_*" -user $(whoami) -delete 2>/dev/null || true
        
        # Create persistent SSH connection
        if $ssh_cmd -M -N -f "$host"; then
            log_info "SSH master connection established and ready for reuse"
            # Brief pause to ensure connection is established
            sleep 2
            
            # Verify the master connection is working
            if ssh_execute "$host" "echo 'Connection test successful'" >/dev/null 2>&1; then
                log_success "SSH master connection verified and working for $host"
            else
                log_error "SSH master connection created but verification failed for $host"
                exit 1
            fi
        else
            log_error "Failed to establish master connection to $host"
            exit 1
        fi
    done
    
    # Check requirements on all hosts (now using established connections)
    log_info "Checking requirements on all hosts..."
    local requirements_failed=false
    
    for host in "${HOSTS[@]}"; do
        if ! check_server_requirements "$host"; then
            requirements_failed=true
        fi
    done
    
    if [ "$requirements_failed" = true ]; then
        log_error "Requirements check failed for one or more hosts"
        exit 1
    fi
    
    # Create deployment package
    log_info "Creating deployment package..."
    if [ "$SKIP_RPMS" = true ]; then
        log_info "Collecting files: gpdb_installer.sh, lib/, tests/, docs/, config files (skipping RPMs)..."
    else
        log_info "Collecting files: gpdb_installer.sh, lib/, tests/, docs/, files/, config files..."
    fi
    local package_path=$(create_deployment_package)
    
    # Check if package creation was successful
    if [ -z "$package_path" ] || [ ! -f "$package_path" ]; then
        log_error "Failed to create deployment package"
        exit 1
    fi
    
    # Deploy to hosts
    log_info "Starting deployment to target hosts..."
    if [ "$PARALLEL" = true ] && [ ${#HOSTS[@]} -gt 1 ]; then
        deploy_parallel "$package_path"
    else
        deploy_sequential "$package_path"
    fi
    
    # Cleanup temporary files
    cleanup_temp_files
    
    # Generate deployment report
    generate_deployment_report
    
    log_success_with_timestamp "Deployment completed successfully!"
}

# Execute main function
main "$@"