# Troubleshooting Guide

This guide covers common issues encountered during Greenplum installation and their solutions.

## Pre-Installation Issues

### 1. Sudo Privileges Error
**Error**: "This script requires sudo privileges"
**Solution**: 
```bash
# Ensure your user is in the sudo group
sudo usermod -aG sudo $USER
# Log out and back in, or run:
newgrp sudo
```

### 2. Missing Dependencies
**Error**: "Dependency 'sshpass' not found"
**Solution**: The installer will automatically attempt to install sshpass if it's missing. If automatic installation fails:

```bash
# CentOS/RHEL 7
sudo yum install sshpass

# CentOS/RHEL 8/Rocky Linux 8
sudo dnf install sshpass

# Ubuntu/Debian
sudo apt-get install sshpass
```

### 3. OS Compatibility Error
**Error**: "Unsupported OS on host"
**Solution**: 
- Ensure all hosts are running CentOS 7/8/9, RHEL 7/8/9, or Rocky Linux 7/8/9
- Check OS version: `cat /etc/os-release`
- Update to supported OS version if necessary

## Installation Phase Issues

### 4. SSH Connection Failed
**Error**: "Failed to copy SSH key to host"
**Solutions**:

**For Single-Node Installations:**
```bash
# Check if SSH key exists
ls -la /home/gpadmin/.ssh/

# Generate SSH key manually
sudo -u gpadmin ssh-keygen -t rsa -N "" -f /home/gpadmin/.ssh/id_rsa

# Set up localhost access
sudo -u gpadmin ssh-keyscan -H localhost >> /home/gpadmin/.ssh/known_hosts
sudo -u gpadmin cat /home/gpadmin/.ssh/id_rsa.pub >> /home/gpadmin/.ssh/authorized_keys
sudo -u gpadmin chmod 600 /home/gpadmin/.ssh/authorized_keys
sudo -u gpadmin chmod 700 /home/gpadmin/.ssh

# Test localhost SSH
sudo -u gpadmin ssh localhost "echo 'SSH working'"
```

**For Multi-Node Installations:**
```bash
# Verify SSH connectivity
ssh user@hostname

# Check if gpadmin user exists
ssh hostname "id gpadmin"

# Verify password is correct
sshpass -p "password" ssh gpadmin@hostname

# Manual SSH key setup
sudo -u gpadmin ssh-keygen -t rsa -N "" -f /home/gpadmin/.ssh/id_rsa
sudo -u gpadmin ssh-copy-id gpadmin@hostname
```

### 5. Package Installation Failed
**Error**: "Greenplum installation failed on host"
**Solutions**:
```bash
# Check if installer file exists
ls -la files/

# Verify installer compatibility
file files/greenplum-db-*.rpm

# Check for dependency issues
sudo rpm -qpR files/greenplum-db-*.rpm

# Install dependencies manually
sudo dnf install -y apr apr-util krb5-devel libevent-devel perl python3-psycopg2 python3.11 readline-devel

# Manual installation test
sudo rpm -ivh files/greenplum-db-*.rpm

# Check disk space
df -h

# Check available memory
free -h
```

### 6. Cluster Initialization Failed
**Error**: "gpinitsystem failed"
**Solutions**:
```bash
# Check gpinitsystem config
cat /usr/local/greenplum-db/gpinitsystem_config

# Verify data directories exist
ls -la /data/primary/

# Check gpadmin permissions
sudo -u gpadmin ls -la /data/primary/

# Manual cluster initialization
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpinitsystem -c /usr/local/greenplum-db/gpinitsystem_config -a
```

## Post-Installation Issues

### 7. Database Connection Failed
**Error**: "Connection refused"
**Solutions**:
```bash
# Check if Greenplum is running
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpstate -s

# Start Greenplum if stopped
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpstart -a

# Check port 5432
netstat -tlnp | grep 5432

# Test connection
sudo -u gpadmin psql -d tdi -h localhost
```

### 8. Segment Status Issues
**Error**: "Segments down"
**Solutions**:
```bash
# Check segment status
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpstate -e

# Restart specific segments
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpstop -r

# Check segment logs
sudo -u gpadmin find /data/primary -name "*.log" -exec tail -f {} \;
```

## Configuration Issues

### 9. Configuration File Errors
**Error**: "Configuration file not found"
**Solutions**:
```bash
# Recreate configuration
rm -f gpdb_config.conf
./gpdb_installer.sh

# Manual configuration
cat > gpdb_config.conf << EOL
GPDB_COORDINATOR_HOST="$(hostname -s)"
GPDB_STANDBY_HOST=""
GPDB_SEGMENT_HOSTS=($(hostname -s))
GPDB_INSTALL_DIR="/usr/local/greenplum-db"
GPDB_DATA_DIR="/data/primary"
EOL
```

### 10. Array Configuration Issues
**Error**: "No segment hosts defined"
**Solutions**:
```bash
# Fix array syntax in config
sed -i 's/GPDB_SEGMENT_HOSTS=.*/GPDB_SEGMENT_HOSTS=('$(hostname -s)')/' gpdb_config.conf

# Or recreate with proper syntax
./gpdb_installer.sh
```

## Network Issues

### 11. Host Communication Problems
**Error**: "Connection timeout"
**Solutions**:
```bash
# Test connectivity between hosts
for host in host1 host2 host3; do
    ping -c 3 $host
    ssh $host "echo 'SSH works'"
done

# Check firewall rules
sudo firewall-cmd --list-all

# Add firewall exception for PostgreSQL
sudo firewall-cmd --permanent --add-port=5432/tcp
sudo firewall-cmd --reload
```

### 12. DNS Resolution Issues
**Error**: "Unknown host"
**Solutions**:
```bash
# Add hosts to /etc/hosts
echo "192.168.1.10 host1" | sudo tee -a /etc/hosts
echo "192.168.1.11 host2" | sudo tee -a /etc/hosts

# Or configure DNS properly
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved
```

## Performance Issues

### 13. Slow Installation
**Solutions**:
```bash
# Check network bandwidth
iperf3 -c hostname

# Use faster network connection
# Consider using local installation files

# Check system resources
top
iostat -x 1
```

### 14. Memory Issues
**Error**: "Out of memory"
**Solutions**:
```bash
# Check available memory
free -h

# Increase swap space
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Add to /etc/fstab for persistence
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## Cleanup and Recovery

### 15. Complete Uninstall
```bash
# Stop Greenplum
sudo -u gpadmin /usr/local/greenplum-db/greenplum-db-7/bin/gpstop -a

# Remove Greenplum installation
sudo rm -rf /usr/local/greenplum-db

# Remove data directories
sudo rm -rf /data/primary

# Remove gpadmin user
sudo userdel -r gpadmin

# Remove SSH keys
sudo rm -rf /home/gpadmin/.ssh
```

### 16. Partial Installation Recovery
```bash
# Check what was installed
ls -la /usr/local/greenplum-db/
ls -la /data/primary/

# Remove partial installation
sudo rm -rf /usr/local/greenplum-db/greenplum-db-7
sudo rm -rf /data/primary/master
sudo rm -rf /data/primary/primary*

# Restart installation
./gpdb_installer.sh
```

## Debug Mode

Enable verbose logging:
```bash
# Run with bash debug mode
bash -x ./gpdb_installer.sh

# Or add debug to script
set -x
./gpdb_installer.sh
set +x
```

## Getting Help

1. **Check logs**: Look for specific error messages in the output
2. **Verify prerequisites**: Ensure all system requirements are met
3. **Test connectivity**: Verify network communication between hosts
4. **Check permissions**: Ensure proper user privileges
5. **Review configuration**: Verify all settings are correct

## Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| "Permission denied" | Insufficient privileges | Run with sudo or add user to sudo group |
| "Connection refused" | Service not running | Start Greenplum with `gpstart -a` |
| "No such file or directory" | Missing installer | Place Greenplum RPM in `files/` directory |
| "Host key verification failed" | SSH key issues | Re-run SSH setup or manually copy keys |
| "Port already in use" | Conflicting service | Stop PostgreSQL or change port |
| "Disk space full" | Insufficient storage | Free up space or use different directory | 