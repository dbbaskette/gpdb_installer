#!/bin/bash

# OpenMetadata Remote Deployment Script
# Deploys OpenMetadata installer to a remote server via SSH

set -e

# Enable debugging - uncomment to see all commands
# set -x

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALLER_SCRIPT="$SCRIPT_DIR/openmetadata_installer.sh"
readonly CONFIG_TEMPLATE="$SCRIPT_DIR/openmetadata_config.conf.template"
readonly README_FILE="$SCRIPT_DIR/OPENMETADATA_README.md"

# Default values
SSH_KEY_FILE=""
TARGET_DIR="/opt/openmetadata_installer"
REMOTE_USER=""
REMOTE_HOST=""
DRY_RUN=false
INSTALL_AFTER_DEPLOY=false

# SSH connection multiplexing variables
SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy OpenMetadata installer to a remote server using the hostname from your config file.

OPTIONS:
    --key-file FILE     SSH private key file to use
    --target-dir DIR    Target directory on remote server (default: /opt/openmetadata_installer)
    --dry-run          Show what would be done without actually doing it
    --install          Run the installer after deployment
    --help             Show this help message

EXAMPLES:
    $0
    $0 --key-file ~/.ssh/id_rsa
    $0 --target-dir /home/user/openmetadata
    $0 --install

Note: This script reads the server hostname from openmetadata_config.conf
EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key-file)
                if [ -n "$2" ]; then
                    SSH_KEY_FILE="$2"
                    shift 2
                else
                    print_status "ERROR" "Option --key-file requires a filename"
                    exit 1
                fi
                ;;
            --target-dir)
                if [ -n "$2" ]; then
                    TARGET_DIR="$2"
                    shift 2
                else
                    print_status "ERROR" "Option --target-dir requires a directory"
                    exit 1
                fi
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --install)
                INSTALL_AFTER_DEPLOY=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                print_status "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                print_status "ERROR" "Unexpected argument: $1"
                print_status "ERROR" "This script reads the server from your config file"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to read server hostname from config file
read_server_from_config() {
    local config_file="$SCRIPT_DIR/openmetadata_config.conf"
    
    if [[ ! -f "$config_file" ]]; then
        print_status "ERROR" "Configuration file not found: $config_file"
        print_status "ERROR" "Please create openmetadata_config.conf first"
        exit 1
    fi
    
    # Read OPENMETADATA_HOST from config file
    local hostname=$(grep '^OPENMETADATA_HOST=' "$config_file" | cut -d'"' -f2)
    
    if [[ -z "$hostname" ]]; then
        print_status "ERROR" "OPENMETADATA_HOST not found in config file"
        exit 1
    fi
    
    # Read OPENMETADATA_SSH_USER from config file
    local ssh_user=$(grep '^OPENMETADATA_SSH_USER=' "$config_file" | cut -d'"' -f2)
    
    if [[ -z "$ssh_user" ]]; then
        print_status "WARN" "OPENMETADATA_SSH_USER not found in config file, using current user"
        ssh_user="$USER"
    fi
    
    # Parse hostname to extract user and host
    if [[ "$hostname" =~ ^([^@]+)@(.+)$ ]]; then
        REMOTE_HOST="${BASH_REMATCH[2]}"
        # Use SSH user from config, not from hostname
        REMOTE_USER="$ssh_user"
    else
        # Use hostname as-is and SSH user from config
        REMOTE_HOST="$hostname"
        REMOTE_USER="$ssh_user"
    fi
    
    print_status "INFO" "Read server from config: $REMOTE_USER@$REMOTE_HOST"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_status "INFO" "Validating prerequisites..."
    
    # Check if required files exist
    local required_files=(
        "$INSTALLER_SCRIPT"
        "$README_FILE"
    )
    
    # Check for config file or template
    if [[ ! -f "$SCRIPT_DIR/openmetadata_config.conf" && ! -f "$CONFIG_TEMPLATE" ]]; then
        print_status "ERROR" "Neither openmetadata_config.conf nor openmetadata_config.conf.template found"
        exit 1
    fi
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_status "ERROR" "Required file not found: $file"
            exit 1
        fi
    done
    
    # Check if installer script is executable
    if [[ ! -x "$INSTALLER_SCRIPT" ]]; then
        print_status "ERROR" "Installer script is not executable: $INSTALLER_SCRIPT"
        exit 1
    fi
    
    # Check SSH key file if specified
    if [[ -n "$SSH_KEY_FILE" ]]; then
        if [[ ! -f "$SSH_KEY_FILE" ]]; then
            print_status "ERROR" "SSH key file not found: $SSH_KEY_FILE"
            exit 1
        fi
        if [[ ! -r "$SSH_KEY_FILE" ]]; then
            print_status "ERROR" "SSH key file is not readable: $SSH_KEY_FILE"
            exit 1
        fi
    fi
    
    print_status "SUCCESS" "Prerequisites validation completed"
}

# Function to build SSH command
build_ssh_command() {
    local ssh_cmd="ssh"
    
    if [[ -n "$SSH_KEY_FILE" ]]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_FILE"
    fi
    
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ssh_cmd="$ssh_cmd -o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=10m"
    
    echo "$ssh_cmd"
}

# Function to build SSH command with pseudo-terminal (for sudo operations)
build_ssh_command_tty() {
    local ssh_cmd="ssh -t"
    
    if [[ -n "$SSH_KEY_FILE" ]]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_FILE"
    fi
    
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ssh_cmd="$ssh_cmd -o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=10m"
    
    echo "$ssh_cmd"
}

# Function to build SCP command
build_scp_command() {
    local scp_cmd="scp"
    
    if [[ -n "$SSH_KEY_FILE" ]]; then
        scp_cmd="$scp_cmd -i $SSH_KEY_FILE"
    fi
    
    scp_cmd="$scp_cmd -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    scp_cmd="$scp_cmd -o ControlPath=$SSH_CONTROL_PATH"
    
    echo "$scp_cmd"
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    print_status "INFO" "Testing SSH connectivity to $REMOTE_USER@$REMOTE_HOST..."
    
    local ssh_cmd=$(build_ssh_command)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would test SSH connectivity"
        return 0
    fi
    
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        print_status "SUCCESS" "SSH connectivity verified"
    else
        print_status "ERROR" "Failed to connect to $REMOTE_USER@$REMOTE_HOST"
        print_status "ERROR" "Please check your SSH configuration and credentials"
        exit 1
    fi
}

# Function to create deployment package
create_deployment_package() {
    print_status "INFO" "Creating deployment package..." >&2
    
    local temp_dir=$(mktemp -d)
    local package_name="openmetadata_installer_$(date +%Y%m%d_%H%M%S).tar.gz"
    local package_path="$SCRIPT_DIR/$package_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would create package: $package_path" >&2
        return 0
    fi
    
    # Copy required files to temp directory
    cp "$INSTALLER_SCRIPT" "$temp_dir/"
    
    # Copy config file if it exists, otherwise copy template
    if [[ -f "$SCRIPT_DIR/openmetadata_config.conf" ]]; then
        cp "$SCRIPT_DIR/openmetadata_config.conf" "$temp_dir/"
        print_status "INFO" "Using local configuration file" >&2
    else
        cp "$CONFIG_TEMPLATE" "$temp_dir/"
        print_status "WARN" "No local config found, using template" >&2
    fi
    
    cp "$README_FILE" "$temp_dir/"
    
    # Copy library files if they exist
    if [[ -d "$SCRIPT_DIR/lib" ]]; then
        cp -r "$SCRIPT_DIR/lib" "$temp_dir/"
    fi
    
    # Create package
    tar -czf "$package_path" -C "$temp_dir" .
    
    # Clean up temp directory
    rm -rf "$temp_dir"
    
    print_status "SUCCESS" "Deployment package created: $package_path" >&2
    echo "$package_path"
}

# Function to deploy to remote server
deploy_to_remote_server() {
    local package_path="$1"
    
    print_status "INFO" "Deploying to $REMOTE_USER@$REMOTE_HOST..."
    
    local ssh_cmd=$(build_ssh_command)
    local scp_cmd=$(build_scp_command)
    local ssh_cmd_tty=$(build_ssh_command_tty)

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would deploy package to $TARGET_DIR"
        return 0
    fi

    # Create target directory on remote server (with sudo and pseudo-terminal)
    print_status "INFO" "Creating target directory on remote server..."
    $ssh_cmd_tty "$REMOTE_USER@$REMOTE_HOST" "sudo mkdir -p $TARGET_DIR && sudo chown $REMOTE_USER:$REMOTE_USER $TARGET_DIR"
    
    # Copy package to remote server
    print_status "INFO" "Copying package to remote server..."
    $scp_cmd "$package_path" "$REMOTE_USER@$REMOTE_HOST:$TARGET_DIR/"

    # Extract package on remote server
    local package_name=$(basename "$package_path")
    print_status "INFO" "Extracting package on remote server..."
    $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd $TARGET_DIR && tar -xzf $package_name && rm $package_name"
    
    # Make installer script executable
    print_status "INFO" "Setting up installer permissions..."
    $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "chmod +x $TARGET_DIR/openmetadata_installer.sh"
    
    print_status "SUCCESS" "Deployment completed successfully"
}

# Function to run installer on remote server
run_remote_installer() {
    print_status "INFO" "Running installer on remote server..."
    
    local ssh_cmd_tty=$(build_ssh_command_tty)
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would run installer on remote server"
        return 0
    fi
    
    # Run installer in interactive mode with pseudo-terminal
    $ssh_cmd_tty "$REMOTE_USER@$REMOTE_HOST" "cd $TARGET_DIR && ./openmetadata_installer.sh"
    
    print_status "SUCCESS" "Remote installation completed"
}

# Function to display deployment summary
display_deployment_summary() {
    echo
    echo "=== OpenMetadata Deployment Summary ==="
    echo "Remote Server: $REMOTE_USER@$REMOTE_HOST"
    echo "Target Directory: $TARGET_DIR"
    echo "SSH Key: ${SSH_KEY_FILE:-Default}"
    echo "Dry Run: $DRY_RUN"
    echo "Auto Install: $INSTALL_AFTER_DEPLOY"
    echo

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "This was a dry run. No changes were made."
    else
        print_status "SUCCESS" "Deployment completed successfully!"
        echo
        echo "Next steps:"
        echo "1. SSH to the remote server: ssh $REMOTE_USER@$REMOTE_HOST"
        echo "2. Navigate to installer: cd $TARGET_DIR"
        if [[ -f "$SCRIPT_DIR/openmetadata_config.conf" ]]; then
            echo "3. Configuration file already deployed and ready"
            echo "4. Run installer: ./openmetadata_installer.sh"
        else
            echo "3. Configure installation: cp openmetadata_config.conf.template openmetadata_config.conf"
            echo "4. Edit configuration: nano openmetadata_config.conf"
            echo "5. Run installer: ./openmetadata_installer.sh"
        fi
        echo
        echo "For more information, see: $TARGET_DIR/OPENMETADATA_README.md"
    fi
}

# Function to cleanup
cleanup() {
    if [[ -n "$PACKAGE_PATH" && -f "$PACKAGE_PATH" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "INFO" "DRY RUN: Would remove package: $PACKAGE_PATH"
        else
            rm -f "$PACKAGE_PATH"
            print_status "INFO" "Cleaned up package: $PACKAGE_PATH"
        fi
    fi
    
    # Clean up SSH control socket
    if [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh -O exit -o ControlPath="$SSH_CONTROL_PATH" "$REMOTE_USER@$REMOTE_HOST" 2>/dev/null || true
        print_status "INFO" "Closed SSH connection"
    fi
}

# Main execution
main() {
    # Parse command line arguments
    parse_arguments "$@"
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Read server from config file
    read_server_from_config
    
    # Show deployment info
    echo "=== OpenMetadata Remote Deployment ==="
    echo "Deploying to: $REMOTE_USER@$REMOTE_HOST"
    echo "Target directory: $TARGET_DIR"
    echo
    
    # Validate prerequisites
    validate_prerequisites
    
    # Test SSH connectivity
    test_ssh_connectivity
    
    # Create deployment package
    PACKAGE_PATH=$(create_deployment_package)
    
    # Deploy to remote server
    deploy_to_remote_server "$PACKAGE_PATH"
    
    # Run installer if requested
    if [[ "$INSTALL_AFTER_DEPLOY" == "true" ]]; then
        run_remote_installer
    fi
    
    # Display summary
    display_deployment_summary
}

# Run main function with all arguments
main "$@"
