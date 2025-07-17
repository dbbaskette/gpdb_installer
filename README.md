# Tanzu Greenplum Database Installer

A comprehensive automation script for installing Greenplum Database v7 on one or more servers with support for single-node and multi-node cluster configurations.

## Features

- **Flexible Deployment**: Support for single-node and multi-node cluster configurations
- **Standby Coordinator**: Optional standby coordinator setup for high availability
- **Automated Setup**: Complete automation of user creation, SSH configuration, and cluster initialization
- **Error Handling**: Comprehensive error checking and informative error messages
- **Dry Run Mode**: Test the installation process without making changes
- **Configuration Persistence**: Save and reuse configuration settings

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

### Network Requirements
- All hosts must be able to communicate via SSH
- Passwordless SSH will be configured automatically
- Port 5432 (PostgreSQL) must be available on the coordinator

## Installation

### 1. Prepare Installation Files

Create the `files` directory and place your Greenplum installer:

```bash
mkdir -p files
# Copy your Greenplum installer to the files directory
# Example: greenplum-db-7.0.0-el7-x86_64.rpm
```

### 2. Run the Installer

```bash
# Make the script executable
chmod +x gpdb_installer.sh

# Run the installer
./gpdb_installer.sh

# Or run in dry-run mode to test
./gpdb_installer.sh --dry-run
```

### 3. Configuration

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

## Configuration File

The installer creates a `gpdb_config.conf` file that stores your configuration:

```bash
# Example configuration
GPDB_COORDINATOR_HOST="coordinator.example.com"
GPDB_STANDBY_HOST="standby.example.com"
GPDB_SEGMENT_HOSTS=(sdw1 sdw2 sdw3)
GPDB_INSTALL_DIR="/usr/local/greenplum-db"
GPDB_DATA_DIR="/data/primary"
```

## Post-Installation

After successful installation:

1. **Connect to the database**:
   ```bash
   sudo -u gpadmin psql -d tdi
   ```

2. **Verify cluster status**:
   ```bash
   sudo -u gpadmin gpstate -s
   ```

3. **Check segment status**:
   ```bash
   sudo -u gpadmin gpstate -e
   ```

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

The installer follows a phased approach:

1. **Preflight Checks**: OS compatibility, dependencies, privileges
2. **Host Setup**: User creation, directory setup, SSH configuration
3. **Binary Installation**: Package distribution and installation
4. **Cluster Initialization**: Database creation and configuration

## Security Considerations

- The installer creates a `gpadmin` user with sudo privileges
- SSH keys are generated and distributed automatically
- Database passwords should be changed after installation
- Consider firewall rules for database ports

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