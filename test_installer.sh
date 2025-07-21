#!/bin/bash

# Test script for Greenplum Installer
# This script tests the installer functionality without requiring actual Greenplum files

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

# Test functions
test_script_syntax() {
    log_info "Testing script syntax..."
    if bash -n gpdb_installer.sh; then
        log_success "Script syntax is valid"
    else
        log_error "Script syntax errors found"
        return 1
    fi
}

test_configuration_creation() {
    log_info "Testing configuration creation..."
    
    # Remove existing config
    rm -f gpdb_config.conf
    
    # Create a mock installer file for testing
    mkdir -p files
    echo "mock-installer" > files/greenplum-db-7.0.0-el7-x86_64.rpm
    
    # Test dry run
    if ./gpdb_installer.sh --dry-run > /dev/null 2>&1; then
        log_success "Configuration creation works"
    else
        log_error "Configuration creation failed"
        return 1
    fi
}

test_config_file_format() {
    log_info "Testing configuration file format..."
    
    if [ -f gpdb_config.conf ]; then
        log_success "Configuration file created"
        
        # Test that it can be sourced
        if source gpdb_config.conf; then
            log_success "Configuration file can be sourced"
        else
            log_error "Configuration file cannot be sourced"
            return 1
        fi
        
        # Check required variables
        if [ -n "$GPDB_COORDINATOR_HOST" ] && [ -n "$GPDB_INSTALL_DIR" ] && [ -n "$GPDB_DATA_DIR" ]; then
            log_success "Required configuration variables are set"
        else
            log_error "Missing required configuration variables"
            return 1
        fi
    else
        log_error "Configuration file not created"
        return 1
    fi
}

test_help_function() {
    log_info "Testing help function..."
    
    if ./gpdb_installer.sh --help | grep -q "Usage:"; then
        log_success "Help function works"
    else
        log_error "Help function failed"
        return 1
    fi
}

test_invalid_option() {
    log_info "Testing invalid option handling..."
    
    if ./gpdb_installer.sh --invalid-option 2>&1 | grep -q "Unknown option"; then
        log_success "Invalid option handling works"
    else
        log_error "Invalid option handling failed"
        return 1
    fi
}

# Main test execution
main() {
    echo -e "${COLOR_GREEN}Starting Greenplum Installer Tests${COLOR_RESET}"
    echo "=========================================="
    
    local tests_passed=0
    local tests_failed=0
    
    # Run tests
    for test in test_script_syntax test_configuration_creation test_config_file_format test_help_function test_invalid_option; do
        if $test; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
        echo ""
    done
    
    # Summary
    echo "=========================================="
    echo -e "${COLOR_GREEN}Test Summary:${COLOR_RESET}"
    echo -e "Tests Passed: ${COLOR_GREEN}$tests_passed${COLOR_RESET}"
    echo -e "Tests Failed: ${COLOR_RED}$tests_failed${COLOR_RESET}"
    
    if [ $tests_failed -eq 0 ]; then
        log_success "All tests passed! The installer is ready for testing."
        echo ""
        echo "Next steps:"
        echo "1. Place a real Greenplum installer RPM in the 'files/' directory"
        echo "2. Run: ./gpdb_installer.sh --dry-run"
        echo "3. Test actual installation on a single node"
    else
        log_error "Some tests failed. Please review the errors above."
        exit 1
    fi
}

# Run tests
main 