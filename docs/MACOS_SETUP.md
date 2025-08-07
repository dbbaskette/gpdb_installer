# macOS Setup for Greenplum Installer

## Pre-Installation (Optional but Recommended)

Since you're running the installer on macOS, you can optionally install `sshpass` beforehand for seamless password authentication:

### Install sshpass via Homebrew
```bash
brew install sshpass
```

### Verify Installation
```bash
which sshpass
# Should show: /opt/homebrew/bin/sshpass (Apple Silicon) or /usr/local/bin/sshpass (Intel)

sshpass -V
# Should show version info
```

## How the Installer Works on macOS

### Package Manager Detection Order:
1. ❌ `yum` - Not available on macOS
2. ❌ `dnf` - Not available on macOS  
3. ❌ `apt-get` - Not available on macOS
4. ✅ `brew` - **This will be used on your Mac**

### Installation Flow:
```bash
./gpdb_installer.sh

# When you answer "y" to password reuse:
Do all hosts use the same SSH password for root user? (y/n) [y]: y
Enter SSH password for root user (will be reused for all hosts): [hidden]

# If sshpass not installed:
Installing sshpass for seamless password authentication...
Using Homebrew to install sshpass (this may take a moment)...
✅ sshpass installed via Homebrew
✅ SSH password stored securely - will be reused for all hosts
```

## Manual Installation (if needed)

If the automatic installation fails, install manually:

```bash
# Install sshpass
brew install sshpass

# Verify it's in your PATH
echo $PATH | grep -E "(homebrew|local)"

# Test sshpass
sshpass -V
```

## Troubleshooting

### Homebrew Not in PATH
If you get "command not found: brew":
```bash
# Add Homebrew to PATH (Apple Silicon)
echo 'export PATH="/opt/homebrew/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

# Or (Intel Mac)
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc  
source ~/.zshrc
```

### Homebrew Not Installed
Install Homebrew first:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### sshpass Installation Fails
Alternative installation methods:
```bash
# Via MacPorts (if you use MacPorts instead)
sudo port install sshpass

# Via manual compilation
wget https://sourceforge.net/projects/sshpass/files/sshpass/1.10/sshpass-1.10.tar.gz
tar -xzf sshpass-1.10.tar.gz
cd sshpass-1.10
./configure
make
sudo make install
```

## What Gets Installed Where

### On Your Mac (Local):
- `sshpass`: `/opt/homebrew/bin/sshpass` (Apple Silicon) or `/usr/local/bin/sshpass` (Intel)
- Used for: Automated SSH password authentication to remote hosts

### On Remote Hosts (Greenplum Servers):
- Greenplum Database RPMs
- PXF RPMs (if configured)
- gpadmin user and SSH keys
- **No sshpass required** on remote hosts

## Ready to Run

Your Mac setup is ready! The installer will:
1. Detect you're on macOS
2. Skip yum/dnf/apt-get attempts
3. Use Homebrew to install sshpass
4. Store your root password securely
5. SSH to your remote Greenplum servers using the stored password

Run the installer normally:
```bash
./gpdb_installer.sh
# or
./pxf_installer.sh
```

The macOS-specific handling is all built-in! 🍎✅