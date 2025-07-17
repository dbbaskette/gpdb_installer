#!/bin/bash

# Greenplum Installer Packaging Script
# Creates a versioned tar.gz distribution package and optionally creates a GitHub release

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

# Check if GitHub CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed. Please install it first: https://cli.github.com/"
    fi
}

# Check if user is authenticated with GitHub
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub. Please run 'gh auth login' first"
    fi
}

# Create GitHub release
create_github_release() {
    local version=$1
    local package_name=$2
    local release_notes=$3
    
    log_info "Creating GitHub release for version $version"
    
    # Check if release already exists
    if gh release view "v$version" &> /dev/null; then
        log_warn "Release v$version already exists. Updating..."
        gh release edit "v$version" --notes "$release_notes"
    else
        # Create new release
        gh release create "v$version" \
            --title "GPDB Installer v$version" \
            --notes "$release_notes" \
            --draft=false \
            --prerelease=false
    fi
    
    log_success "GitHub release created/updated: v$version"
}

# Upload asset to GitHub release
upload_github_asset() {
    local version=$1
    local package_name=$2
    
    log_info "Uploading $package_name to GitHub release v$version"
    
    # Upload the tar.gz file
    gh release upload "v$version" "$package_name" --clobber
    
    log_success "Asset uploaded successfully: $package_name"
}

# Generate release notes
generate_release_notes() {
    local version=$1
    
    # Get the latest commit message
    local latest_commit=$(git log -1 --pretty=format:"%s")
    
    # Get recent commits for changelog
    local recent_commits=$(git log --oneline -10 | sed 's/^/- /')
    
    cat << EOF
## GPDB Installer v$version

### What's New
- Automated Greenplum Database installation
- Support for single-node and multi-node cluster configurations
- Comprehensive preflight checks and validation
- Interactive and non-interactive installation modes
- Extensive testing and validation scripts

### Installation
1. Download the \`$package_name\` file
2. Extract: \`tar -xzf $package_name\`
3. Follow the README.md instructions

### Recent Changes
$recent_commits

### System Requirements
- RHEL/CentOS/Rocky Linux 7, 8, or 9
- SSH access to target servers
- Greenplum Database v7 installer RPM

For detailed installation instructions, see the README.md file.
EOF
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
    
    echo "$package_name"
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
    local create_release=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --release|-r)
                create_release=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
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
    local package_name=$(create_package "$dist_dir" "$version")
    
    # Cleanup
    cleanup "$dist_dir"
    
    echo ""
    log_success "Packaging completed successfully!"
    log_info "Package: $package_name"
    
    # Create GitHub release if requested
    if [ "$create_release" = true ]; then
        echo ""
        log_info "Creating GitHub release..."
        
        # Check prerequisites
        check_gh_cli
        check_gh_auth
        
        # Generate release notes
        local release_notes=$(generate_release_notes "$version" "$package_name")
        
        # Create release
        create_github_release "$version" "$package_name" "$release_notes"
        
        # Upload asset
        upload_github_asset "$version" "$package_name"
        
        log_success "GitHub release created successfully!"
        log_info "Release URL: https://github.com/dbbaskette/gpdb_installer/releases/tag/v$version"
    else
        log_info "Ready for distribution"
        log_info "Use --release flag to create a GitHub release"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Creates a versioned tar.gz package of the GPDB installer"
    echo "Version is read from the VERSION file"
    echo ""
    echo "OPTIONS:"
    echo "  --release, -r    Create a GitHub release and upload the package"
    echo "  --help, -h       Show this help message"
    echo ""
    echo "The package will include:"
    echo "- Main installer script (gpdb_installer.sh)"
    echo "- Documentation (README.md, TROUBLESHOOTING.md, etc.)"
    echo "- Test scripts (test_installer.sh, dry_run_test.sh, etc.)"
    echo "- Configuration templates"
    echo "- Mock installer files"
    echo ""
    echo "Examples:"
    echo "  $0                    # Create package only"
    echo "  $0 --release          # Create package and GitHub release"
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
    --release|-r)
        main "$@"
        ;;
    *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac 