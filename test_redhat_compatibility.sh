#!/bin/bash

# Red Hat Linux Compatibility Test Script
# Tests the installer scripts for Red Hat Linux compatibility

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
}

# Test command availability
test_command() {
    local cmd=$1
    local description=$2
    
    if command -v "$cmd" >/dev/null 2>&1; then
        log_success "$description ($cmd) - Available"
        return 0
    else
        log_error "$description ($cmd) - Not available"
        return 1
    fi
}

# Test file existence
test_file() {
    local file=$1
    local description=$2
    
    if [ -f "$file" ]; then
        log_success "$description ($file) - Exists"
        return 0
    else
        log_error "$description ($file) - Missing"
        return 1
    fi
}

# Test script syntax
test_script_syntax() {
    local script=$1
    local description=$2
    
    if bash -n "$script" 2>/dev/null; then
        log_success "$description ($script) - Syntax OK"
        return 0
    else
        log_error "$description ($script) - Syntax errors"
        return 1
    fi
}

# Test Red Hat specific commands
test_redhat_commands() {
    log_info "Testing Red Hat Linux specific commands..."
    
    # Test memory check command
    if [ -f "/proc/meminfo" ]; then
        local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ]; then
            log_success "Memory check (/proc/meminfo) - Working"
        else
            log_error "Memory check (/proc/meminfo) - Failed"
        fi
    else
        log_warn "Memory check (/proc/meminfo) - Not available (not on Linux)"
    fi
    
    # Test disk space check command
    if df -k . >/dev/null 2>&1; then
        log_success "Disk space check (df -k) - Working"
    else
        log_error "Disk space check (df -k) - Failed"
    fi
    
    # Test hostname command
    if hostname >/dev/null 2>&1; then
        log_success "Hostname command - Working"
    else
        log_error "Hostname command - Failed"
    fi
}

# Test script compatibility
test_script_compatibility() {
    log_info "Testing script compatibility..."
    
    local scripts=(
        "gpdb_installer.sh:Main installer script"
        "push_to_server.sh:Push deployment script"
        "package.sh:Package creation script"
        "test_installer.sh:Test script"
        "dry_run_test.sh:Dry run test script"
        "interactive_test.sh:Interactive test script"
    )
    
    local failed=0
    
    for script_info in "${scripts[@]}"; do
        IFS=':' read -r script description <<< "$script_info"
        
        if [ -f "$script" ]; then
            if test_script_syntax "$script" "$description"; then
                log_success "$description - Syntax check passed"
            else
                log_error "$description - Syntax check failed"
                failed=$((failed + 1))
            fi
        else
            log_warn "$description - File not found"
        fi
    done
    
    return $failed
}

# Test required files
test_required_files() {
    log_info "Testing required files..."
    
    local files=(
        "VERSION:Version file"
        "gpdb_config.conf:Configuration template"
        "test_config.conf:Test configuration"
    )
    
    local failed=0
    
    for file_info in "${files[@]}"; do
        IFS=':' read -r file description <<< "$file_info"
        
        if test_file "$file" "$description"; then
            log_success "$description - Found"
        else
            log_error "$description - Missing"
            failed=$((failed + 1))
        fi
    done
    
    return $failed
}

# Test basic commands
test_basic_commands() {
    log_info "Testing basic command availability..."
    
    local commands=(
        "bash:Bash shell"
        "tar:Tar archive utility"
        "grep:Grep text search"
        "awk:Awk text processing"
        "sed:Sed text editor"
        "ssh:SSH client"
        "scp:SCP file transfer"
    )
    
    local failed=0
    
    for cmd_info in "${commands[@]}"; do
        IFS=':' read -r cmd description <<< "$cmd_info"
        
        if test_command "$cmd" "$description"; then
            log_success "$description - Available"
        else
            log_error "$description - Missing"
            failed=$((failed + 1))
        fi
    done
    
    return $failed
}

# Main test function
main() {
    echo -e "${COLOR_GREEN}Red Hat Linux Compatibility Test${COLOR_RESET}"
    echo "=========================================="
    
    local total_failed=0
    
    # Test basic commands
    if ! test_basic_commands; then
        total_failed=$((total_failed + 1))
    fi
    
    # Test required files
    if ! test_required_files; then
        total_failed=$((total_failed + 1))
    fi
    
    # Test script compatibility
    if ! test_script_compatibility; then
        total_failed=$((total_failed + 1))
    fi
    
    # Test Red Hat specific commands
    test_redhat_commands
    
    echo ""
    echo "=========================================="
    if [ $total_failed -eq 0 ]; then
        log_success "All compatibility tests passed!"
        log_info "Scripts should work on Red Hat Linux systems"
    else
        log_error "$total_failed test categories failed"
        log_warn "Some issues detected - review the errors above"
    fi
    
    return $total_failed
}

# Run main test
main "$@" 