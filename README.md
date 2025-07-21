# Tanzu Greenplum Database Installer

A comprehensive automation script for installing Greenplum Database v7 on one or more servers with support for single-node and multi-node cluster configurations.

## Features

- **Flexible Deployment**: Support for single-node and multi-node cluster configurations
- **Standby Coordinator**: Optional standby coordinator setup for high availability
- **Automated Setup**: Complete automation of user creation, SSH configuration, and cluster initialization
- **Error Handling**: Comprehensive error checking and informative error messages
- **Dry Run Mode**: Test the installation process without making changes
- **Configuration Persistence**: Save and reuse configuration settings
- **Red Hat Linux Compatible**: Optimized for RHEL/CentOS/Rocky Linux systems
- **Remote Deployment**: Push scripts to remote servers via SSH
- **GitHub Integration**: Create releases and upload packages automatically

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
```

### 2. Test Red Hat Compatibility (Optional)

```bash
# Test compatibility with Red Hat Linux systems
./test_redhat_compatibility.sh
```

### 3. Run the Installer

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

### Remote Deployment

Deploy the installer to remote servers:

```bash
# Deploy to a single server
./push_to_server.sh user@server1.example.com

# Deploy to multiple servers
./push_to_server.sh user@server1 user@server2 user@server3

# Deploy with custom SSH key and target directory
./push_to_server.sh --key-file ~/.ssh/id_rsa --target-dir /opt/gpdb_installer user@server1

# Test deployment without actually doing it
./push_to_server.sh --dry-run user@server1
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

- **gpdb_installer.sh**: Main installation script
- **test_installer.sh**: Automated testing script
- **dry_run_test.sh**: Comprehensive dry-run testing
- **interactive_test.sh**: Interactive testing mode
- **package.sh**: Package creation and GitHub release script
- **push_to_server.sh**: Remote deployment script
- **test_redhat_compatibility.sh**: Red Hat Linux compatibility testing

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