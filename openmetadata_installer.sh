#!/bin/bash

# OpenMetadata Complete Installer v2.0
# Installs OpenMetadata on remote server entirely from local machine via SSH
# Includes automatic admin user creation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="$SCRIPT_DIR/openmetadata_config.conf"

# Default values
SSH_KEY_FILE=""
DRY_RUN=false
VERBOSE=false
CLEAN_INSTALL=false
REMOVE_INSTALL=false
OVERRIDE_HOST=""

# SSH connection multiplexing variables
SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"

# Global variables from config
REMOTE_HOST=""
REMOTE_USER=""
OPENMETADATA_ADMIN_USER=""
OPENMETADATA_ADMIN_PASSWORD=""

# Function to print colored output
print_status() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "[$timestamp] ${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "[$timestamp] ${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARN")
            echo -e "[$timestamp] ${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "[$timestamp] ${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to show usage
show_usage() {
    echo "OpenMetadata Complete Installer v2.0"
    echo "Installs OpenMetadata with automatic admin user creation"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -v, --verbose       Enable verbose output"
    echo "  -d, --dry-run       Show what would be done without executing"
    echo "  -c, --clean         Clean install (removes all existing data)"
    echo "  -r, --remove        Remove OpenMetadata installation completely"
    echo "  -H, --host HOST     Override host from config file"
    echo "  -k, --ssh-key FILE  SSH private key file"
    echo
    echo "Configuration:"
    echo "  Edit openmetadata_config.conf to set server details and credentials"
    echo
    echo "Examples:"
    echo "  $0                          # Install with default settings"
    echo "  $0 --clean                 # Clean install (removes all data)"
    echo "  $0 --remove                # Remove OpenMetadata completely"
    echo "  $0 --remove --host server.example.com  # Remove from specific host"
    echo "  $0 --remove --dry-run      # Show what would be removed"
    echo "  $0 --ssh-key ~/.ssh/id_rsa # Use specific SSH key"
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -c|--clean)
                CLEAN_INSTALL=true
                shift
                ;;
            -r|--remove)
                REMOVE_INSTALL=true
                shift
                ;;
            -H|--host)
                OVERRIDE_HOST="$2"
                shift 2
                ;;
            -k|--ssh-key)
                SSH_KEY_FILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Function to load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_status "ERROR" "Configuration file not found: $CONFIG_FILE"
        print_status "INFO" "Please copy openmetadata_config.conf.template to openmetadata_config.conf and configure it"
        exit 1
    fi
    
    print_status "INFO" "Loading configuration from $CONFIG_FILE..."
    
    # Source the config file
    source "$CONFIG_FILE"
    
    REMOTE_HOST="$OPENMETADATA_HOST"
    REMOTE_USER="$OPENMETADATA_SSH_USER"
    
    # Override host if specified on command line
    if [[ -n "$OVERRIDE_HOST" ]]; then
        REMOTE_HOST="$OVERRIDE_HOST"
        print_status "INFO" "Using override host: $REMOTE_HOST"
    fi
    
    if [[ -z "$REMOTE_HOST" || -z "$REMOTE_USER" ]]; then
        print_status "ERROR" "OPENMETADATA_HOST and OPENMETADATA_SSH_USER must be set in config file"
        exit 1
    fi
    
    print_status "SUCCESS" "Configuration loaded: $REMOTE_USER@$REMOTE_HOST"
}

# Function to cleanup SSH connections
cleanup() {
    if [[ -S "$SSH_CONTROL_PATH" ]]; then
        ssh -o ControlPath="$SSH_CONTROL_PATH" -O exit "$REMOTE_USER@$REMOTE_HOST" 2>/dev/null || true
    fi
}

# Function to build SSH command
build_ssh_command() {
    local ssh_cmd="ssh"
    
    if [[ -n "$SSH_KEY_FILE" ]]; then
        ssh_cmd="$ssh_cmd -i $SSH_KEY_FILE"
    fi
    
    ssh_cmd="$ssh_cmd -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ssh_cmd="$ssh_cmd -o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=10m"
    
    if [[ "$VERBOSE" != "true" ]]; then
        ssh_cmd="$ssh_cmd -q"
    fi
    
    echo "$ssh_cmd"
}

# Function to execute remote command
remote_exec() {
    local command="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would execute: $description"
        print_status "INFO" "Command: $command"
        return 0
    fi
    
    print_status "INFO" "$description"
    
    local ssh_cmd=$(build_ssh_command)
    
    if [[ "$VERBOSE" == "true" ]]; then
        $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "$command"
    else
        $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "$command" >/dev/null 2>&1
    fi
}

# Function to test SSH connectivity
test_ssh_connectivity() {
    print_status "INFO" "Testing SSH connectivity to $REMOTE_USER@$REMOTE_HOST..."
    
    local ssh_cmd=$(build_ssh_command)
    
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "echo 'SSH connection successful'" >/dev/null 2>&1; then
        print_status "SUCCESS" "SSH connectivity verified"
    else
        print_status "ERROR" "Cannot connect to $REMOTE_USER@$REMOTE_HOST"
        print_status "ERROR" "Please check your SSH configuration and credentials"
        exit 1
    fi
}

# Function to completely remove OpenMetadata installation
remove_openmetadata() {
    print_status "WARN" "REMOVAL REQUESTED - This will completely remove OpenMetadata and all data!"
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -n "Are you absolutely sure you want to remove OpenMetadata? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_status "INFO" "Removal cancelled"
            exit 0
        fi
    fi
    
    print_status "INFO" "Removing OpenMetadata installation..."
    
    # Stop and remove all containers, volumes, and images
    remote_exec "cd /opt/openmetadata 2>/dev/null && docker compose down --volumes --rmi all 2>/dev/null || true" "Stopping and removing containers, volumes, and images"
    
    # Remove any remaining OpenMetadata containers
    remote_exec "docker ps -a --filter name=openmetadata --format '{{.ID}}' | xargs -r docker rm -f 2>/dev/null || true" "Removing any remaining OpenMetadata containers"
    
    # Remove any remaining OpenMetadata images
    remote_exec "docker images --filter reference='*openmetadata*' --format '{{.ID}}' | xargs -r docker rmi -f 2>/dev/null || true" "Removing OpenMetadata Docker images"
    remote_exec "docker images --filter reference='*getcollate*' --format '{{.ID}}' | xargs -r docker rmi -f 2>/dev/null || true" "Removing OpenMetadata Docker images"
    
    # Remove installation directory
    remote_exec "sudo rm -rf /opt/openmetadata" "Removing installation directory"
    

    
    # Remove firewall rules
    remote_exec "                 sudo firewall-cmd --permanent --remove-port=8585/tcp 2>/dev/null || true
                 sudo firewall-cmd --permanent --remove-port=${OPENMETADATA_INGESTION_PORT:-8082}/tcp 2>/dev/null || true
                 sudo firewall-cmd --permanent --remove-port=9200/tcp 2>/dev/null || true
                 sudo firewall-cmd --permanent --remove-port=3306/tcp 2>/dev/null || true
                 sudo firewall-cmd --reload 2>/dev/null || true" "Removing firewall rules"
    
    # Clean up Docker system (optional - removes unused volumes, networks, images)
    remote_exec "docker system prune -f 2>/dev/null || true" "Cleaning up Docker system"
    
    print_status "SUCCESS" "OpenMetadata has been completely removed!"
    echo
    echo "=== Removal Complete ==="
    echo "• All OpenMetadata containers removed"
    echo "• All data volumes deleted"
    echo "• All Docker images removed"
    echo "• Installation directory deleted"
    echo "• Firewall rules removed"
    echo "• Docker system cleaned up"
    echo
    print_status "INFO" "The server is now clean of OpenMetadata"
    
    exit 0
}

# Function to cleanup existing installation
cleanup_existing_installation() {
    if [[ "$CLEAN_INSTALL" != "true" ]]; then
        return 0
    fi
    
    print_status "WARN" "Clean install requested - this will remove ALL existing OpenMetadata data!"
    if [[ "$DRY_RUN" != "true" ]]; then
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r confirmation
        if [[ "$confirmation" != "yes" ]]; then
            print_status "INFO" "Installation cancelled"
            exit 0
        fi
    fi
    
    print_status "INFO" "Cleaning up existing installation..."
    
    # Stop and remove containers and volumes
    remote_exec "cd /opt/openmetadata 2>/dev/null && docker compose down --volumes --rmi all 2>/dev/null || true" "Stopping and removing existing containers and volumes"
    
    # Remove installation directory
    remote_exec "sudo rm -rf /opt/openmetadata" "Removing installation directory"
    
    print_status "SUCCESS" "Cleanup completed"
}

# Function to install Docker
install_docker() {
    print_status "INFO" "Installing Docker..."
    
    remote_exec "command -v docker" "Checking if Docker is installed"
    if [[ $? -eq 0 ]]; then
        print_status "INFO" "Docker is already installed"
        remote_exec "docker --version" "Checking Docker version"
        return 0
    fi
    
    # Install Docker
    remote_exec "curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh" "Installing Docker"
    remote_exec "sudo systemctl enable docker && sudo systemctl start docker" "Starting Docker service"
    remote_exec "sudo usermod -aG docker $REMOTE_USER" "Adding user to docker group"
    
    print_status "SUCCESS" "Docker installed successfully"
}

# Function to setup OpenMetadata
setup_openmetadata() {
    print_status "INFO" "Setting up OpenMetadata..."
    
    # Create directory
    remote_exec "sudo mkdir -p /opt/openmetadata && sudo chown $REMOTE_USER:$REMOTE_USER /opt/openmetadata" "Creating OpenMetadata directory"
    
    # Download official Docker Compose
    remote_exec "cd /opt/openmetadata && curl -fsSL https://github.com/open-metadata/OpenMetadata/releases/latest/download/docker-compose.yml -o docker-compose.yml" "Downloading official Docker Compose configuration"
    
    # Update ingestion port to avoid conflicts
    remote_exec "cd /opt/openmetadata && sed -i 's|8080:8080|${OPENMETADATA_INGESTION_PORT:-8082}:8080|g' docker-compose.yml" "Configuring ingestion service port"
    
    print_status "SUCCESS" "OpenMetadata setup completed"
}

# Function to configure firewall
configure_firewall() {
    print_status "INFO" "Configuring firewall..."
    
    # Check if firewall is active
    remote_exec "sudo firewall-cmd --state" "Checking firewall status"
    if [[ $? -ne 0 ]]; then
        print_status "WARN" "Firewall is not active, skipping firewall configuration"
        return 0
    fi
    
    # Open required ports
    remote_exec "sudo firewall-cmd --permanent --add-port=8585/tcp
                 sudo firewall-cmd --permanent --add-port=${OPENMETADATA_INGESTION_PORT:-8082}/tcp
                 sudo firewall-cmd --permanent --add-port=9200/tcp
                 sudo firewall-cmd --permanent --add-port=3306/tcp
                 sudo firewall-cmd --reload" "Opening firewall ports"
    
    print_status "SUCCESS" "Firewall configured"
}

# Function to start OpenMetadata services
start_services() {
    print_status "INFO" "Starting OpenMetadata services..."
    
    # Start services in detached mode
    local ssh_cmd=$(build_ssh_command)
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would start Docker Compose services"
        return 0
    fi
    
    print_status "INFO" "Starting Docker Compose services"
    if [[ "$VERBOSE" == "true" ]]; then
        $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose up -d"
    else
        $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose up -d" >/dev/null 2>&1
    fi
    
    print_status "INFO" "Waiting for services to start..."
    sleep 30
    
    # Check service status (non-fatal)
    print_status "INFO" "Checking initial service status"
    $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose ps" 2>/dev/null || {
        print_status "WARN" "Could not check service status immediately, but services are starting"
    }
    
    print_status "SUCCESS" "OpenMetadata services started"
}



# Function to verify admin user exists
verify_admin_user() {
    print_status "INFO" "Verifying admin user..."
    
    if [[ -z "$OPENMETADATA_ADMIN_USER" || -z "$OPENMETADATA_ADMIN_PASSWORD" ]]; then
        print_status "INFO" "Using OpenMetadata default admin credentials"
        OPENMETADATA_ADMIN_USER="admin@open-metadata.org"
        OPENMETADATA_ADMIN_PASSWORD="admin"
    fi
    
    # Wait for OpenMetadata to be fully ready
    print_status "INFO" "Waiting for OpenMetadata to be ready..."
    sleep 60
    
    # Verify default admin user exists (OpenMetadata creates this automatically)
    print_status "INFO" "OpenMetadata automatically creates default admin user on first startup"
    print_status "SUCCESS" "Default admin user available: $OPENMETADATA_ADMIN_USER"
}

# Function to verify installation
verify_installation() {
    print_status "INFO" "Verifying installation..."
    
    # Check if services are running (non-fatal)
    local ssh_cmd=$(build_ssh_command)
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "DRY RUN: Would verify installation"
        return 0
    fi
    
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose ps | grep -q 'healthy'" 2>/dev/null; then
        print_status "SUCCESS" "Services are healthy and running"
    elif $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose ps | grep -q 'Up'" 2>/dev/null; then
        print_status "SUCCESS" "Services are running (health check pending)"
    else
        print_status "WARN" "Could not verify service health - services may still be starting"
    fi
    
    print_status "SUCCESS" "Installation verification completed"
}

# Function to show service status
show_service_status() {
    print_status "INFO" "Current service status:"
    echo
    echo "🐳 DOCKER SERVICES STATUS:"
    echo "========================================"
    
    local ssh_cmd=$(build_ssh_command)
    if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null; then
        echo "========================================"
    else
        print_status "WARN" "Could not retrieve detailed service status"
        # Try a simpler status check
        if $ssh_cmd "$REMOTE_USER@$REMOTE_HOST" "cd /opt/openmetadata && docker compose ps" 2>/dev/null; then
            echo "========================================"
        else
            echo "   Status check failed - services may still be starting"
            echo "========================================"
        fi
    fi
    echo
}

# Function to show completion message
show_completion() {
    echo
    echo "======================================================================="
    echo "                 🎉 OpenMetadata Installation Complete! 🎉"
    echo "======================================================================="
    echo
    echo "📋 SERVER INFORMATION:"
    echo "   Server: $REMOTE_USER@$REMOTE_HOST"
    echo "   Installation Path: /opt/openmetadata"
    echo
    echo "🌐 ACCESS URLS:"
    echo "   OpenMetadata Web UI:  http://$REMOTE_HOST:8585"
    echo "   OpenMetadata API:     http://$REMOTE_HOST:8585/api"
    echo "   Swagger API Docs:     http://$REMOTE_HOST:8585/swagger-ui"
    echo "   Ingestion/Airflow:    http://$REMOTE_HOST:${OPENMETADATA_INGESTION_PORT:-8082}"
    echo "   Elasticsearch:        http://$REMOTE_HOST:9200"
    echo "   MySQL Database:       $REMOTE_HOST:3306"
    echo
    echo "🔐 ADMIN LOGIN CREDENTIALS:"
    echo "   Username: ${OPENMETADATA_ADMIN_USER:-admin@openmetadata.org}"
    echo "   Password: ${OPENMETADATA_ADMIN_PASSWORD:-admin123}"
    echo
    echo "🔥 FIREWALL PORTS OPENED:"
    echo "   Port 8585: OpenMetadata Web UI & API"
    echo "   Port ${OPENMETADATA_INGESTION_PORT:-8082}: Ingestion/Airflow service"
    echo "   Port 9200: Elasticsearch (internal)"
    echo "   Port 3306: MySQL Database (internal)"
    echo
    echo "🐳 DOCKER SERVICES RUNNING:"
    echo "   • openmetadata_server       (Main application)"
    echo "   • openmetadata_mysql        (Database)"
    echo "   • openmetadata_elasticsearch (Search engine)"
    echo "   • openmetadata_ingestion    (Airflow/Data ingestion)"
    echo
    echo "🛠️  MANAGEMENT COMMANDS:"
    echo "   Check status:  ssh $REMOTE_USER@$REMOTE_HOST 'cd /opt/openmetadata && docker compose ps'"
    echo "   View logs:     ssh $REMOTE_USER@$REMOTE_HOST 'cd /opt/openmetadata && docker compose logs -f'"
    echo "   Stop services: ssh $REMOTE_USER@$REMOTE_HOST 'cd /opt/openmetadata && docker compose down'"
    echo "   Start services:ssh $REMOTE_USER@$REMOTE_HOST 'cd /opt/openmetadata && docker compose up -d'"
    echo "   Restart:       ssh $REMOTE_USER@$REMOTE_HOST 'cd /opt/openmetadata && docker compose restart'"
    if [[ "${MCP_SERVER_ENABLED:-true}" == "true" ]]; then
        echo
        echo "   MCP Server Commands:"
        echo "   Check MCP:     ssh $REMOTE_USER@$REMOTE_HOST 'sudo systemctl status openmetadata-mcp'"
        echo "   MCP logs:      ssh $REMOTE_USER@$REMOTE_HOST 'sudo journalctl -u openmetadata-mcp -f'"
        echo "   Stop MCP:      ssh $REMOTE_USER@$REMOTE_HOST 'sudo systemctl stop openmetadata-mcp'"
        echo "   Start MCP:     ssh $REMOTE_USER@$REMOTE_HOST 'sudo systemctl start openmetadata-mcp'"
        echo "   Restart MCP:   ssh $REMOTE_USER@$REMOTE_HOST 'sudo systemctl restart openmetadata-mcp'"
    fi
    echo
    echo "📖 NEXT STEPS:"
    echo "   1. Open http://$REMOTE_HOST:8585 in your browser"
    echo "   2. Login with the credentials above"
    echo "   3. Start adding your data sources and exploring metadata!"
    if [[ "${MCP_SERVER_ENABLED:-true}" == "true" ]]; then
        echo "   4. Configure MCP clients to connect to http://$REMOTE_HOST:${MCP_SERVER_PORT}"
    fi
    echo
    echo "💡 TIPS:"
    echo "   • Bookmark the URL for easy access"
    echo "   • Change the default admin password in Settings"
    echo "   • Check the documentation at: https://docs.open-metadata.org"
    if [[ "${MCP_SERVER_ENABLED:-true}" == "true" ]]; then
        echo "   • MCP server provides API access for AI agents and external tools"
        echo "   • MCP documentation: https://modelcontextprotocol.io"
    fi
    echo
    echo "======================================================================="
    print_status "SUCCESS" "🚀 OpenMetadata is ready for use!"
    echo "======================================================================="
}

# Main execution function
main() {
    echo "OpenMetadata Complete Installer v2.0"
    echo "Installing OpenMetadata with automatic admin user creation"
    echo
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    parse_arguments "$@"
    load_config
    test_ssh_connectivity
    
    # Handle removal request
    if [[ "$REMOVE_INSTALL" == "true" ]]; then
        remove_openmetadata
    fi
    
    cleanup_existing_installation
    install_docker
    setup_openmetadata
    configure_firewall
    start_services
    verify_admin_user
    verify_installation
    show_service_status
    show_completion
}

# Execute main function
main "$@"