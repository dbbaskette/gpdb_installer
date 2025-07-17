#!/bin/bash

# Greenplum Installer Packaging Script
# Creates a versioned tar.gz distribution package

set -e

# Colors for output
COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'

log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1" >&2
    exit 1
}

# Read version from VERSION file
get_version() {
    if [ -f "VERSION" ]; then
        cat VERSION | tr -d ' \t\n\r'
    else
        log_error "VERSION file not found"
    fi
}

# Create distribution directory
create_dist_dir() {
    local version=$1
    local dist_dir="gpdb-installer-${version}"
    
    echo "Creating distribution directory: $dist_dir" >&2
    
    # Remove existing directory if it exists
    if [ -d "$dist_dir" ]; then
        rm -rf "$dist_dir"
    fi
    
    # Create new directory
    mkdir -p "$dist_dir"
    
    echo "$dist_dir"
}

# Copy files to distribution directory
copy_files() {
    local dist_dir=$1
    
    echo "Copying files to distribution directory..." >&2
    
    # Core installer files
    cp gpdb_installer.sh "$dist_dir/"
    cp VERSION "$dist_dir/"
    
    # Documentation files
    cp README.md "$dist_dir/"
    cp TROUBLESHOOTING.md "$dist_dir/"
    cp installation_plan.md "$dist_dir/"
    cp TESTING_SUMMARY.md "$dist_dir/"
    
    # Test scripts
    cp test_installer.sh "$dist_dir/"
    cp dry_run_test.sh "$dist_dir/"
    cp interactive_test.sh "$dist_dir/"
    
    # Configuration templates
    cp test_config.conf "$dist_dir/"
    
    # Create files directory
    mkdir -p "$dist_dir/files"
    cp files/greenplum-db-7.0.0-el7.x86_64.rpm "$dist_dir/files/" 2>/dev/null || true
    
    # Make scripts executable
    chmod +x "$dist_dir/gpdb_installer.sh"
    chmod +x "$dist_dir/test_installer.sh"
    chmod +x "$dist_dir/dry_run_test.sh"
    chmod +x "$dist_dir/interactive_test.sh"
    
    echo "Files copied successfully" >&2
}

# Create tar.gz package
create_package() {
    local dist_dir=$1
    local version=$2
    local package_name="gpdb-installer-${version}.tar.gz"
    
    echo "Creating package: $package_name" >&2
    
    # Remove existing package if it exists
    if [ -f "$package_name" ]; then
        rm -f "$package_name"
    fi
    
    # Create tar.gz
    tar -czf "$package_name" "$dist_dir"
    
    if [ $? -eq 0 ]; then
        echo "Package created successfully: $package_name" >&2
        
        # Show package info
        local package_size=$(du -h "$package_name" | cut -f1)
        echo "Package size: $package_size" >&2
        
        # List contents
        echo "Package contents:" >&2
        tar -tzf "$package_name" | head -20
        if [ $(tar -tzf "$package_name" | wc -l) -gt 20 ]; then
            echo "... and $(($(tar -tzf "$package_name" | wc -l) - 20)) more files"
        fi
    else
        echo "Failed to create package" >&2
        return 1
    fi
}

# Clean up distribution directory
cleanup() {
    local dist_dir=$1
    
    echo "Cleaning up distribution directory..." >&2
    rm -rf "$dist_dir"
    echo "Cleanup completed" >&2
}

# Main packaging function
main() {
    echo -e "${COLOR_GREEN}Greenplum Installer Packaging Script${COLOR_RESET}"
    echo "=========================================="
    
    # Get version
    local version=$(get_version)
    log_info "Building version: $version"
    
    # Create distribution directory
    local dist_dir=$(create_dist_dir "$version")
    
    # Copy files
    copy_files "$dist_dir"
    
    # Create package
    create_package "$dist_dir" "$version"
    
    # Cleanup
    cleanup "$dist_dir"
    
    echo ""
    log_success "Packaging completed successfully!"
    log_info "Package: gpdb-installer-${version}.tar.gz"
    log_info "Ready for distribution"
}

# Show usage
show_usage() {
    echo "Usage: $0"
    echo ""
    echo "Creates a versioned tar.gz package of the GPDB installer"
    echo "Version is read from the VERSION file"
    echo ""
    echo "The package will include:"
    echo "- Main installer script (gpdb_installer.sh)"
    echo "- Documentation (README.md, TROUBLESHOOTING.md, etc.)"
    echo "- Test scripts (test_installer.sh, dry_run_test.sh, etc.)"
    echo "- Configuration templates"
    echo "- Mock installer files"
}

# Parse command line arguments
case "${1:-}" in
    --help|-h)
        show_usage
        exit 0
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac 