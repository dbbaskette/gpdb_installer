# Where sshpass Gets Installed

## Installation Locations by Operating System

### **RHEL/CentOS/Rocky Linux/AlmaLinux (YUM/DNF)**
```bash
sudo yum install sshpass
# or
sudo dnf install sshpass
```
**Installed to:** `/usr/bin/sshpass`

Package details:
- Package name: `sshpass`
- Repository: EPEL (Extra Packages for Enterprise Linux)
- Binary path: `/usr/bin/sshpass`
- Man page: `/usr/share/man/man1/sshpass.1.gz`

### **Ubuntu/Debian (APT)**
```bash
sudo apt-get update
sudo apt-get install sshpass
```
**Installed to:** `/usr/bin/sshpass`

Package details:
- Package name: `sshpass`
- Repository: Main repository
- Binary path: `/usr/bin/sshpass`
- Man page: `/usr/share/man/man1/sshpass.1.gz`

### **macOS (Homebrew)**
```bash
brew install sshpass
```
**Installed to:** `/opt/homebrew/bin/sshpass` (Apple Silicon) or `/usr/local/bin/sshpass` (Intel)

Package details:
- Formula name: `sshpass`
- Binary path: `/opt/homebrew/bin/sshpass` or `/usr/local/bin/sshpass`
- Symlinked to system PATH automatically

### **Amazon Linux**
```bash
sudo yum install sshpass
```
**Installed to:** `/usr/bin/sshpass`

## How the Installer Finds sshpass

The installer uses the `command -v sshpass` command which checks your system's `$PATH` environment variable to locate the binary. This works regardless of the specific installation location because:

1. All package managers add the binary to a standard PATH directory
2. The `command -v` utility searches all PATH directories
3. No hardcoded paths are needed in the installer

## Installation Process in the Installer

```bash
# Check if sshpass exists
if ! command -v sshpass >/dev/null 2>&1; then
    # Try different package managers in order
    if command -v yum >/dev/null 2>&1; then
        sudo yum install -y sshpass
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y sshpass
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v brew >/dev/null 2>&1; then
        brew install sshpass
    fi
fi
```

## Verification Commands

After installation, you can verify sshpass is installed:

```bash
# Check if installed
command -v sshpass

# Check version
sshpass -V

# Check manual page
man sshpass
```

## Common Installation Issues

### **EPEL Repository Required (RHEL/CentOS)**
If you get "No package sshpass available":
```bash
# Install EPEL repository first
sudo yum install epel-release
# Then install sshpass
sudo yum install sshpass
```

### **Permission Issues (macOS)**
If Homebrew installation fails:
```bash
# Fix Homebrew permissions
brew doctor
# Then retry
brew install sshpass
```

### **APT Update Required (Ubuntu/Debian)**
If package not found:
```bash
# Update package lists first
sudo apt-get update
# Then install
sudo apt-get install sshpass
```

## Manual Installation from Source

If package managers fail, you can compile from source:

```bash
# Download source
wget https://sourceforge.net/projects/sshpass/files/sshpass/1.09/sshpass-1.09.tar.gz
tar -xzf sshpass-1.09.tar.gz
cd sshpass-1.09

# Compile and install
./configure
make
sudo make install
```

This installs to `/usr/local/bin/sshpass` by default.

## Summary

- **Linux systems**: `/usr/bin/sshpass`
- **macOS (Homebrew)**: `/opt/homebrew/bin/sshpass` or `/usr/local/bin/sshpass`
- **Manual compile**: `/usr/local/bin/sshpass`

The installer automatically detects the location using `command -v sshpass`, so the exact path doesn't matter as long as it's in your system's PATH.