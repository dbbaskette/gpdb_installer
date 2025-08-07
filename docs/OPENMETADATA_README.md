# OpenMetadata Installer

A comprehensive automation script for installing OpenMetadata v1.8.0 on Linux servers with Docker support and MCP (Model Context Protocol) Server integration.

## Features

- **Docker-Based Installation**: Automated Docker and Docker Compose installation
- **MCP Server Integration**: Built-in support for Model Context Protocol server
- **Flexible Configuration**: Comprehensive configuration options via template file
- **Multi-OS Support**: Compatible with RHEL/CentOS/Rocky Linux and Ubuntu/Debian
- **Automated Setup**: Complete automation of Docker installation, service configuration, and initialization
- **Error Handling**: Comprehensive error checking and informative error messages
- **Dry Run Mode**: Test the installation process without making changes
- **Service Management**: Built-in scripts for starting, stopping, and monitoring services

## Prerequisites

### System Requirements
- **Operating System**: CentOS 7/8/9, RHEL 7/8/9, Rocky Linux 7/8/9, Ubuntu 18.04+, Debian 10+
- **Architecture**: x86_64
- **Memory**: Minimum 4GB RAM (8GB recommended)
- **Disk Space**: At least 10GB free space for installation

### Software Dependencies
- `curl` - For downloading Docker Compose (will be installed automatically if missing)
- `sudo` - For privileged operations
- `openssl` - For generating security keys (usually pre-installed)

### SSH User Requirements
- **Sudo Access**: The SSH user must have sudo privileges for Docker installation
- **Sudo Group**: User should be in the `sudo` or `wheel` group
- **Interactive Sudo**: The installer will prompt for sudo password when needed
- **Docker Group**: The user will be added to the docker group during installation

**Docker Dependencies** (installed automatically):
- Docker CE (Community Edition)
- Docker Compose v2.20.0

### Network Requirements
- Internet connectivity for Docker image downloads
- Port 8585 (OpenMetadata API) must be available
- Port 3000 (OpenMetadata UI) must be available
- Port 8080 (MCP Server) must be available (if enabled)
- Port 3306 (MySQL) must be available

## Installation

### Option 1: Local Installation (on target server)

#### 1. Prepare Installation

```bash
# Clone or download the installer
git clone <repository-url>
cd gpdb_installer

# Make the script executable
chmod +x openmetadata_installer.sh
```

#### 2. Configure Installation

```bash
# Copy the configuration template
cp openmetadata_config.conf.template openmetadata_config.conf

# Edit the configuration file with your settings
nano openmetadata_config.conf
```

#### 3. Run the Installer

```bash
# Run the installer
./openmetadata_installer.sh

# Or run in dry-run mode to test
./openmetadata_installer.sh --dry-run
```

### Option 2: Remote Deployment (from local machine)

#### 1. Deploy to Remote Server

```bash
# Deploy installer to remote server (reads hostname from config)
./push_openmetadata_to_server.sh

# Deploy with custom SSH key
./push_openmetadata_to_server.sh --key-file ~/.ssh/id_rsa

# Deploy to custom directory
./push_openmetadata_to_server.sh --target-dir /home/user/openmetadata

# Deploy and run installer automatically
./push_openmetadata_to_server.sh --install
```

**Note**: The script reads the server hostname and SSH user from your `openmetadata_config.conf` file. The SSH user must have sudo privileges for Docker installation.

#### 2. SSH to Remote Server and Configure

```bash
# SSH to the remote server
ssh user@remote-server.example.com

# Navigate to installer directory
cd /opt/openmetadata_installer

# If you have a local config file, it will be deployed automatically
# Otherwise, configure installation:
cp openmetadata_config.conf.template openmetadata_config.conf
nano openmetadata_config.conf

# Run the installer
./openmetadata_installer.sh
```

**Note**: If you have a local `openmetadata_config.conf` file, it will be automatically deployed to the remote server, so you can skip the configuration step.

## Configuration

The installer uses a configuration file (`openmetadata_config.conf`) with the following key settings:

### Basic Configuration
```bash
# Server host where OpenMetadata will be installed
OPENMETADATA_HOST="openmetadata-server.example.com"

# SSH user for remote deployment (must have sudo privileges)
OPENMETADATA_SSH_USER="admin"

# OpenMetadata version to install
OPENMETADATA_VERSION="1.8.0"

# Service ports
OPENMETADATA_PORT=8585
OPENMETADATA_UI_PORT=3000
```

### Database Configuration
```bash
# Database type and connection details
OPENMETADATA_DB_TYPE="mysql"  # Options: mysql, postgresql
OPENMETADATA_DB_HOST="localhost"
OPENMETADATA_DB_PORT=3306
OPENMETADATA_DB_NAME="openmetadata_db"
OPENMETADATA_DB_USER="openmetadata_user"
OPENMETADATA_DB_PASSWORD="your-secure-db-password-here"
```

### Admin User Configuration
```bash
# Initial admin user
OPENMETADATA_ADMIN_EMAIL="admin@example.com"
OPENMETADATA_ADMIN_PASSWORD="your-secure-admin-password-here"
```

### MCP Server Configuration
```bash
# Model Context Protocol server settings
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=8080
MCP_SERVER_HOST="0.0.0.0"  # Bind to all interfaces for external access
```

### Security Configuration
```bash
# Security keys (auto-generated if not provided)
OPENMETADATA_SECRET_KEY="your-secret-key-here"
OPENMETADATA_ENCRYPTION_KEY="your-encryption-key-here"
```

## Usage Examples

### Basic Installation
```bash
./openmetadata_installer.sh
# Accept defaults for basic setup
```

### Custom Configuration
```bash
# Edit configuration first
nano openmetadata_config.conf

# Run installer
./openmetadata_installer.sh
```

### Dry Run (Testing)
```bash
./openmetadata_installer.sh --dry-run
```

### Clean Installation
```bash
./openmetadata_installer.sh --clean
```

## Service Management

After installation, the following management scripts are created:

### Start Services
```bash
./start_openmetadata.sh
```

### Stop Services
```bash
./stop_openmetadata.sh
```

### Check Status
```bash
./status_openmetadata.sh
```

### Manual Docker Commands
```bash
# View logs
docker-compose logs -f

# Stop services
docker-compose down

# Start services
docker-compose up -d

# Restart services
docker-compose restart
```

## Post-Installation

After successful installation:

1. **Access OpenMetadata UI**:
   ```
   http://your-server-hostname:3000
   ```

2. **Access OpenMetadata API**:
   ```
   http://your-server-hostname:8585
   ```

3. **Access MCP Server** (if enabled):
   ```
   http://your-server-hostname:8080
   ```

4. **Login with admin credentials**:
   - Email: As configured in `OPENMETADATA_ADMIN_EMAIL`
   - Password: As configured in `OPENMETADATA_ADMIN_PASSWORD`

## External Access Configuration

The installer configures all services to accept external connections:

- **OpenMetadata Server**: Binds to `0.0.0.0:8585`
- **OpenMetadata UI**: Binds to `0.0.0.0:3000`
- **MCP Server**: Binds to `0.0.0.0:8080` (if enabled)

### Firewall Configuration

Ensure your firewall allows access to the required ports:

```bash
# For RHEL/CentOS/Rocky Linux
sudo firewall-cmd --permanent --add-port=8585/tcp
sudo firewall-cmd --permanent --add-port=3000/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload

# For Ubuntu/Debian
sudo ufw allow 8585/tcp
sudo ufw allow 3000/tcp
sudo ufw allow 8080/tcp
```

### Security Considerations

When exposing services externally:

1. **Use HTTPS**: Consider setting up a reverse proxy with SSL/TLS
2. **Network Security**: Restrict access to trusted IP ranges
3. **Strong Passwords**: Use strong admin passwords
4. **Regular Updates**: Keep Docker images updated
5. **Monitoring**: Monitor access logs for suspicious activity

## MCP Server Integration

The Model Context Protocol (MCP) server allows LLMs to access OpenMetadata data for context-aware operations. The installer automatically:

1. **Installs MCP Server**: Downloads and configures the OpenMetadata MCP server
2. **Configures Connection**: Sets up connection to OpenMetadata API
3. **Starts Service**: Launches MCP server on configured port

### MCP Server Configuration
The MCP server is configured via `mcp-server/config.json`:
```json
{
  "openmetadata": {
    "host": "localhost",
    "port": 8585,
    "admin_email": "admin@example.com",
    "admin_password": "admin-password"
  },
  "server": {
    "host": "localhost",
    "port": 8080
  }
}
```

## Troubleshooting

### Common Issues

#### 1. Docker Installation Fails
**Error**: "Unsupported operating system for Docker installation"
**Solution**: Ensure you're running a supported OS (RHEL/CentOS/Rocky Linux or Ubuntu/Debian)

#### 2. Port Already in Use
**Error**: "Port XXXX is already in use"
**Solution**: 
```bash
# Check what's using the port
netstat -tuln | grep :8585

# Stop conflicting service or change port in config
```

#### 3. Services Won't Start
**Error**: "OpenMetadata server failed to start"
**Solution**:
```bash
# Check Docker logs
docker-compose logs openmetadata-server

# Check system resources
docker stats

# Restart services
docker-compose restart
```

#### 4. Database Connection Issues
**Error**: "MySQL failed to start"
**Solution**:
```bash
# Check MySQL container logs
docker logs openmetadata-mysql

# Check disk space
df -h

# Restart MySQL container
docker restart openmetadata-mysql
```

### Log Files

Logs are available in multiple locations:
- **Docker logs**: `docker-compose logs -f`
- **Application logs**: `/opt/openmetadata/logs/`
- **System logs**: `journalctl -u docker`

### Performance Tuning

For production deployments:

1. **Increase Memory**: Ensure at least 8GB RAM available
2. **Optimize Storage**: Use SSD storage for better performance
3. **Network**: Ensure stable network connectivity
4. **Docker Resources**: Adjust Docker daemon memory limits

## Security Considerations

1. **Change Default Passwords**: Always change default admin passwords
2. **Secure Keys**: Use strong secret and encryption keys
3. **Network Security**: Configure firewall rules appropriately
4. **Docker Security**: Keep Docker and images updated
5. **Access Control**: Limit access to OpenMetadata services

## Upgrading

To upgrade OpenMetadata:

1. **Backup Data**: Export any important configurations
2. **Update Version**: Change `OPENMETADATA_VERSION` in config
3. **Re-run Installer**: Run installer with `--force` flag
4. **Verify**: Check that all services are running correctly

## Support

For issues and questions:

1. **Check Logs**: Review Docker and application logs
2. **Documentation**: Refer to [OpenMetadata Documentation](https://docs.open-metadata.org/latest)
3. **Community**: Join the [OpenMetadata Community](https://slack.open-metadata.org/)

## License

This installer is provided as-is for educational and development purposes. OpenMetadata is licensed under the Apache License 2.0. 