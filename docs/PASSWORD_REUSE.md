# SSH Password Reuse Feature

## Overview
The Greenplum installer supports storing your root SSH password securely in memory and reusing it across all servers to eliminate repeated password prompts during installation.

## How It Works

### 1. **Password Collection**
- The installer asks if all hosts use the same root password
- If yes, you enter the password once
- Password is stored securely in memory using environment variables

### 2. **Automated Authentication**
- Uses `sshpass` utility for automated password authentication
- If `sshpass` is not installed, the installer will attempt to install it automatically
- Supports multiple package managers: `yum`, `dnf`, `apt-get`, `brew`

### 3. **SSH Connection Multiplexing**
- Creates persistent SSH master connections to each host
- Subsequent commands reuse these connections without re-authentication
- Connections persist for 10 minutes by default

## Benefits

✅ **No Repeated Prompts**: Enter password once, use everywhere  
✅ **Faster Installation**: Persistent connections speed up remote operations  
✅ **Automatic Setup**: Installs and configures `sshpass` automatically  
✅ **Multi-Platform**: Works on RHEL, CentOS, Ubuntu, Debian, macOS  

## Usage

### Main Installer
```bash
./gpdb_installer.sh
```
When prompted:
- Answer "y" to "Do all hosts use the same SSH password for root user?"
- Enter your root password once
- The installer handles the rest automatically

### PXF Installer  
```bash
./pxf_installer.sh
```
Same process - password is collected once and reused for all hosts.

## Requirements

### Automatic Installation (Recommended)
- Installer will attempt to install `sshpass` automatically
- Requires sudo access on the local machine

### Manual Installation (If Needed)
```bash
# RHEL/CentOS/Fedora
sudo yum install sshpass
# or
sudo dnf install sshpass

# Ubuntu/Debian
sudo apt-get install sshpass

# macOS
brew install sshpass
```

## Security Notes

- Passwords are stored only in memory during installation
- Environment variables are cleared when installation completes
- SSH connections are cleaned up automatically
- No passwords are written to disk or log files

## Troubleshooting

### "sshpass not available" Warning
If you see this warning, the installer will fall back to manual password entry for each connection. To resolve:
1. Install sshpass manually (see commands above)
2. Re-run the installer

### Connection Issues
If SSH connections fail despite correct password:
1. Verify root SSH access is enabled on target hosts
2. Check firewall settings (port 22)
3. Ensure root login is permitted in `/etc/ssh/sshd_config`

### Manual Password Entry
If you prefer to enter passwords manually:
- Answer "n" to the password reuse question
- You'll be prompted for each connection individually

## Examples

### Successful Password Reuse
```
SSH Access Configuration:
  Target hosts: server1 server2 server3

💡 Password Reuse: The installer can store your root password securely in memory
   and reuse it across all servers to avoid repeated prompts.

Do all hosts use the same SSH password for root user? (y/n) [y]: y
Enter SSH password for root user (will be reused for all hosts): [hidden]
✅ SSH password stored securely - will be reused for all hosts
✅ sshpass available - fully automated password authentication enabled
```

### Installing sshpass Automatically
```
Installing sshpass for seamless password authentication...
✅ sshpass installed via yum
✅ SSH password stored securely - will be reused for all hosts
```

This feature significantly improves the installation experience by eliminating repetitive password entry while maintaining security best practices.