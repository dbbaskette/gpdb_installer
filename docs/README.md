# Tanzu Greenplum Database & OpenMetadata Installer

A comprehensive automation suite for installing Greenplum Database v7 and OpenMetadata v1.8.0 on Linux servers with support for single-node and multi-node cluster configurations, Docker-based deployments, and enhanced management capabilities.

## Features

### Greenplum Database Installer
- **Flexible Deployment**: Support for single-node and multi-node cluster configurations
- **Standby Coordinator**: Optional standby coordinator setup for high availability
- **Automated Setup**: Complete automation of user creation, SSH configuration, and cluster initialization
- **Error Handling**: Comprehensive error checking and informative error messages
- **Dry Run Mode**: Test the installation process without making changes
- **Configuration Persistence**: Save and reuse configuration settings
- **Red Hat Linux Compatible**: Optimized for RHEL/CentOS/Rocky Linux systems
- **Remote Deployment**: Push scripts to remote servers via SSH
- **GitHub Integration**: Create releases and upload packages automatically
- **Optional Extensions**: Install and enable MADlib, PostGIS, and the Greenplum Spark Connector

### OpenMetadata Installer
- **Docker-Based Installation**: Automated Docker and Docker Compose installation
- **Flexible Configuration**: Comprehensive configuration options via `openmetadata_config.conf` template file for services like ingestion.
- **Multi-OS Support**: Compatible with RHEL/CentOS/Rocky Linux and Ubuntu/Debian
- **Automated Setup**: Complete automation of Docker installation, service configuration, and initialization
- **Service Management**: Built-in scripts for starting, stopping, and monitoring services
- **Full Lifecycle Management**: Includes `--clean` for reinstallation, and `--remove` for complete uninstallation.
- **Configurable Host**: Use `--host` to override the target server from the config file.
- **Comprehensive Output**: Detailed completion summary with URLs, ports, admin credentials, and management commands.

## Prerequisites

### System Requirements
- **Operating System**: CentOS 7/8/9, RHEL 7/8/9, or Rocky Linux 7/8/9
- **Architecture**: x86_64
- **Memory**: Minimum 8GB RAM (16GB recommended)
- **Disk Space**: At least 10GB free space for installation

### Software Dependencies
- `sshpass` - For automated SSH key distribution (will be installed automatically if missing)
- `sudo` - For privileged operations
- `ssh` - For remote host communication
- `rpm` - For package installation

**Greenplum Dependencies** (installed automatically):
- `apr` and `apr-util` - Apache Portable Runtime
- `krb5-devel` - Kerberos development libraries
- `libevent-devel` - Event notification library
- `perl` - Perl programming language
- `python3-psycopg2` - PostgreSQL adapter for Python
- `python3.11` - Python 3.11 runtime
- `readline-devel` - Readline development libraries

### Network Requirements
- All hosts must be able to communicate via SSH
- Passwordless SSH will be configured automatically
- For single-node installations, SSH is configured for localhost access
- For multi-node installations, SSH keys are distributed across all hosts
- Port 5432 (PostgreSQL) must be available on the coordinator

## Installation

### 1. Prepare Installation Files

Create the `files` directory and place your Greenplum installer:

```bash
mkdir -p files
# Copy your Greenplum installer to the files directory
# Example: greenplum-db-7.0.0-el7-x86_64.rpm

# Optional extensions (auto-detected if present or install can be forced via config):
# - MADlib RPM (e.g., madlib-oss-gp7-*.rpm)
# - PostGIS RPM (e.g., postgis-gp7-*.rpm)
# - Spark Connector tarball (e.g., greenplum-connector-apache-spark-scala_2.12-*.tar.gz)
```

### 2. Test Red Hat Compatibility (Optional)

```bash
# Test compatibility with Red Hat Linux systems
./test_redhat_compatibility.sh
```

### 3. Run the Greenplum Installer

```bash
# Make the script executable
chmod +x gpdb_installer.sh

# Run the installer
./gpdb_installer.sh

# Or run in dry-run mode to test
./gpdb_installer.sh --dry-run
```

### 4. Run the OpenMetadata Installer

```bash
# Make the script executable
chmod +x openmetadata_installer.sh

# Run the installer for full installation
./openmetadata_installer.sh

# Run in dry-run mode to test
./openmetadata_installer.sh --dry-run

# Clean up and reinstall OpenMetadata
./openmetadata_installer.sh --clean

# Completely remove OpenMetadata installation
./openmetadata_installer.sh --remove

# Install to a specific host, overriding the config file
./openmetadata_installer.sh --host user@your-remote-host
```

### 5. Configuration

The installer will prompt you for the following information:

- **Coordinator Hostname**: The host that will serve as the coordinator (default: current hostname)
- **Segment Hosts**: Comma-separated list of hosts for data segments
- **Standby Coordinator**: Optional standby coordinator for high availability
- **Installation Directory**: Where to install Greenplum (default: `/usr/local/greenplum-db`)
- **Data Directory**: Where to store data files (default: `/data/primary`)

## Usage Examples

### Single-Node Installation
```bash
./gpdb_installer.sh
# Accept defaults for single-node setup
```

### Multi-Node Installation
```bash
./gpdb_installer.sh
# Enter segment hostnames: sdw1,sdw2,sdw3
# Enter standby hostname: sdw4
```

### Dry Run (Testing)
```bash
./gpdb_installer.sh --dry-run
```

## Remote Deployment

You can deploy the installer package to a single remote server (typically the coordinator or primary node) using `push_to_server.sh`. Once deployed, SSH into that server and run the installer, which will handle installation and configuration across all cluster nodes.

**Example: Deploy to a single server**
```bash
./push_to_server.sh user@coordinator.example.com
```

**Example: Deploy with custom SSH key and target directory**
```bash
./push_to_server.sh --key-file ~/.ssh/id_rsa --target-dir /opt/gpdb_installer user@coordinator.example.com
```

> **Note:** You only need to push the installer to one server. The installer will distribute binaries and configuration to all cluster nodes from there.

**To install:**
```bash
ssh user@coordinator.example.com
cd /opt/gpdb_installer
./gpdb_installer.sh
```

### Package Creation and GitHub Release

Create a distribution package and optionally create a GitHub release:

```bash
# Create package only
./package.sh

# Create package and GitHub release
./package.sh --release
```

## Red Hat Linux Compatibility

The installer has been optimized for Red Hat Linux systems (RHEL, CentOS, Rocky Linux):

- **Memory Detection**: Uses `/proc/meminfo` instead of `free` command
- **Disk Space**: Uses `df -k` for better compatibility
- **Hostname**: Uses standard `hostname` command
- **Package Management**: Optimized for RPM-based systems
- **System Commands**: Compatible with Red Hat system utilities

Run the compatibility test to verify your system:

```bash
./test_redhat_compatibility.sh
```

## Scripts Overview

The installer includes several scripts for different purposes:

- **gpdb_installer.sh**: Main Greenplum installation script
- **openmetadata_installer.sh**: Main OpenMetadata installation and management script
- **cleanup_greenplum.sh**: Script to clean up a Greenplum installation
- **datalake_installer.sh**: Script for Datalake installation (if applicable)
- **test_installer.sh**: Automated testing script for Greenplum
- **dry_run_test.sh**: Comprehensive dry-run testing for Greenplum
- **interactive_test.sh**: Interactive testing mode for Greenplum
- **package.sh**: Package creation and GitHub release script
- **push_to_server.sh**: Remote deployment script (used by gpdb_installer)
- **test_redhat_compatibility.sh**: Red Hat Linux compatibility testing
- **test_config.sh**: Test script for configuration parsing
- **test_ssh.sh**: Test script for SSH connectivity
- **test_validation.sh**: Test script for validation functions

## Configuration File

The installers use configuration files for customizable settings:

- **gpdb_config.conf.template**: Template for Greenplum Database configuration
- **openmetadata_config.conf.template**: Template for OpenMetadata installation configuration

Example `gpdb_config.conf` configuration:

```bash
# Example configuration
GPDB_COORDINATOR_HOST="coordinator.example.com"
GPDB_STANDBY_HOST="standby.example.com"
GPDB_SEGMENT_HOSTS=(sdw1 sdw2 sdw3)
GPDB_INSTALL_DIR="/usr/local/greenplum-db"
GPDB_DATA_DIR="/data/primary"

# Optional components
INSTALL_PXF=true
INSTALL_MADLIB=false
INSTALL_POSTGIS=false
INSTALL_SPARK_CONNECTOR=false
DATABASE_NAME="tdi"
```

Example `openmetadata_config.conf` configuration:

```bash
# OpenMetadata service configuration
OPENMETADATA_HOST="big-data-004.kuhn-labs.com" # Hostname or IP of the OpenMetadata server
OPENMETADATA_VERSION="1.8.10-release" # OpenMetadata version to install

# Docker configuration (true/false)
INSTALL_DOCKER=true

# Database configuration (OpenMetadata uses MySQL by default)
# You can use existing MySQL/PostgreSQL or let OpenMetadata create its own
OPENMETADATA_DB_TYPE="mysql"  # Options: mysql, postgresql
OPENMETADATA_DB_HOST="localhost"
OPENMETADATA_DB_PORT=3306
OPENMETADATA_DB_NAME="openmetadata_db"
OPENMETADATA_DB_USER="openmetadata_user"
OPENMETADATA_DB_PASSWORD="your-secure-db-password-here"

# OpenMetadata admin user configuration - default admin user (created automatically)
OPENMETADATA_ADMIN_USER="admin@open-metadata.org"
OPENMETADATA_ADMIN_PASSWORD="admin"

# OpenMetadata Ingestion/Airflow service configuration
OPENMETADATA_INGESTION_PORT=8082 # Port for the Ingestion/Airflow service (e.g., 8082 to avoid conflict with 8080)

# Storage configuration
OPENMETADATA_DATA_DIR="/opt/openmetadata/data"
OPENMETADATA_LOGS_DIR="/opt/openmetadata/logs"

# SSH configuration for remote deployment
OPENMETADATA_SSH_USER="root" # User for SSH connection to remote host
SSH_KEY_FILE="" # Path to SSH private key file (optional)
```

## Post-Installation

After successful installation:

1. **Connect to the database**:
   ```bash
   sudo -u gpadmin bash -c 'source ~/.bashrc && psql -d tdi'
   ```

2. **Verify cluster status**:
   ```bash
   sudo -u gpadmin bash -c 'source ~/.bashrc && gpstate -s'
   ```

3. **Check segment status**:
   ```bash
   sudo -u gpadmin bash -c 'source ~/.bashrc && gpstate -e'
   ```

> **Note:** The installer configures the gpadmin user's `~/.bashrc` to source the Greenplum environment (`greenplum_path.sh`) and set required variables. Always use `source ~/.bashrc` in your session or scripts before running Greenplum commands as gpadmin.

## Troubleshooting

### Common Issues

**SSH Connection Failed**
- Ensure all hosts are reachable via SSH
- Verify the gpadmin user exists on all hosts
- Check that the provided password is correct

**Package Installation Failed**
- Verify the Greenplum installer is in the `files` directory
- Ensure the installer is compatible with your OS version
- Check that rpm is available on all hosts

**Cluster Initialization Failed**
- Verify all hosts can communicate with each other
- Check that the data directories have proper permissions
- Ensure the coordinator host is accessible from all segments

**Permission Denied Errors**
- Run the script with a user that has sudo privileges
- Ensure the gpadmin user has proper permissions on data directories

### Logs and Debugging

The installer provides detailed logging with color-coded output:
- 🔵 **Blue**: Information messages
- 🟢 **Green**: Success messages
- 🟡 **Yellow**: Warning messages
- 🔴 **Red**: Error messages

### Manual Recovery

If the installation fails partway through:

1. **Clean up partial installation**:
   ```bash
   # Remove gpadmin user and directories
   sudo userdel -r gpadmin
   sudo rm -rf /data/primary /usr/local/greenplum-db
   ```

2. **Restart the installer**:
   ```bash
   ./gpdb_installer.sh
   ```

## Architecture

The installers follow a phased approach:

1.  **Preflight Checks**: OS compatibility, dependencies, privileges
2.  **Host Setup**: User creation, directory setup, SSH configuration
3.  **Binary Installation**: Package distribution and installation (for Greenplum), or Docker image deployment (for OpenMetadata)
4.  **Cluster Initialization**: Database creation and configuration (for Greenplum), or service startup and configuration (for OpenMetadata)

## Security Considerations

- The installer creates a `gpadmin` user with sudo privileges for Greenplum.
- SSH keys are generated and distributed automatically for Greenplum.
- Database passwords should be changed after installation.
- Consider firewall rules for database and application ports.

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the installation logs for specific error messages
3. Ensure all prerequisites are met
4. Verify network connectivity between hosts

## Version Compatibility

This installer is designed for Greenplum Database v7. For other versions:
- Modify the installer file detection patterns
- Update the installation paths and commands
- Adjust the configuration file format if needed 