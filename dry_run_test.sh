#!/bin/bash

# Comprehensive Dry-Run Test for Greenplum Installer
# This script tests the installer functionality using dry-run mode

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

# Setup test environment
setup_test_env() {
    log_info "Setting up test environment..."
    
    # Backup existing config if it exists
    if [ -f gpdb_config.conf ]; then
        cp gpdb_config.conf gpdb_config.conf.backup
    fi
    
    # Use test configuration
    cp test_config.conf gpdb_config.conf
    
    # Ensure files directory exists with mock installer
    mkdir -p files
    echo "# Mock Greenplum installer file for testing" > files/greenplum-db-7.0.0-el7-x86_64.rpm
    
    log_success "Test environment setup complete"
}

# Test 1: Basic dry-run functionality
test_basic_dry_run() {
    log_info "Test 1: Basic dry-run functionality"
    
    # Run dry-run and capture output
    local output=$(./gpdb_installer.sh --dry-run 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "Dry-run completed successfully"
        
        # Check for expected output patterns
        if echo "$output" | grep -q "Dry run mode enabled"; then
            log_success "Dry-run mode detection works"
        else
            log_warn "Dry-run mode detection not found in output"
        fi
        
        if echo "$output" | grep -q "Pre-flight Checks"; then
            log_success "Preflight checks section found"
        else
            log_warn "Preflight checks section not found"
        fi
        
        if echo "$output" | grep -q "Setting Up Hosts"; then
            log_success "Host setup section found"
        else
            log_warn "Host setup section not found"
        fi
        
        if echo "$output" | grep -q "Installing Greenplum Binaries"; then
            log_success "Installation section found"
        else
            log_warn "Installation section not found"
        fi
        
        if echo "$output" | grep -q "Initializing Greenplum Cluster"; then
            log_success "Cluster initialization section found"
        else
            log_warn "Cluster initialization section not found"
        fi
        
    else
        log_error "Dry-run failed with exit code $exit_code"
        echo "Output: $output"
        return 1
    fi
}

# Test 2: Configuration validation
test_config_validation() {
    log_info "Test 2: Configuration validation"
    
    # Test with valid config
    if source gpdb_config.conf; then
        log_success "Configuration file can be sourced"
        
        # Check required variables
        if [ -n "$GPDB_COORDINATOR_HOST" ] && [ -n "$GPDB_INSTALL_DIR" ] && [ -n "$GPDB_DATA_DIR" ]; then
            log_success "All required configuration variables are set"
        else
            log_error "Missing required configuration variables"
            return 1
        fi
        
        # Check array format
        if [ ${#GPDB_SEGMENT_HOSTS[@]} -gt 0 ]; then
            log_success "Segment hosts array is properly formatted"
        else
            log_error "Segment hosts array is empty or malformed"
            return 1
        fi
        
    else
        log_error "Configuration file cannot be sourced"
        return 1
    fi
}

# Test 3: Help functionality
test_help_function() {
    log_info "Test 3: Help functionality"
    
    local help_output=$(./gpdb_installer.sh --help 2>&1)
    
    if echo "$help_output" | grep -q "Usage:"; then
        log_success "Help function works correctly"
    else
        log_error "Help function failed"
        return 1
    fi
}

# Test 4: Invalid option handling
test_invalid_options() {
    log_info "Test 4: Invalid option handling"
    
    local error_output=$(./gpdb_installer.sh --invalid-option 2>&1)
    
    if echo "$error_output" | grep -q "Unknown option"; then
        log_success "Invalid option handling works correctly"
    else
        log_error "Invalid option handling failed"
        return 1
    fi
}

# Test 5: Script syntax validation
test_script_syntax() {
    log_info "Test 5: Script syntax validation"
    
    if bash -n gpdb_installer.sh; then
        log_success "Script syntax is valid"
    else
        log_error "Script syntax errors found"
        return 1
    fi
}

# Test 6: Function structure validation
test_function_structure() {
    log_info "Test 6: Function structure validation"
    
    # Check for required functions
    local required_functions=("preflight_checks" "setup_hosts" "install_greenplum" "initialize_cluster" "configure_installation")
    
    for func in "${required_functions[@]}"; do
        if grep -q "^$func()" gpdb_installer.sh; then
            log_success "Function '$func' found"
        else
            log_error "Required function '$func' not found"
            return 1
        fi
    done
}

# Test 7: Error handling validation
test_error_handling() {
    log_info "Test 7: Error handling validation"
    
    # Check for error handling patterns
    if grep -q "log_error" gpdb_installer.sh; then
        log_success "Error logging functions are used"
    else
        log_warn "No error logging found"
    fi
    
    if grep -q "set -e" gpdb_installer.sh; then
        log_success "Exit on error is enabled"
    else
        log_warn "Exit on error not enabled"
    fi
}

# Test 8: Color output validation
test_color_output() {
    log_info "Test 8: Color output validation"
    
    # Check for color definitions
    if grep -q "COLOR_GREEN" gpdb_installer.sh && grep -q "COLOR_RED" gpdb_installer.sh; then
        log_success "Color output is implemented"
    else
        log_warn "Color output not fully implemented"
    fi
}

# Cleanup test environment
cleanup_test_env() {
    log_info "Cleaning up test environment..."
    
    # Restore original config if it existed
    if [ -f gpdb_config.conf.backup ]; then
        mv gpdb_config.conf.backup gpdb_config.conf
    else
        rm -f gpdb_config.conf
    fi
    
    log_success "Test environment cleanup complete"
}

# Main test execution
main() {
    echo -e "${COLOR_GREEN}Starting Comprehensive Dry-Run Tests${COLOR_RESET}"
    echo "=================================================="
    
    local tests_passed=0
    local tests_failed=0
    
    # Setup
    setup_test_env
    
    # Run tests
    local tests=(
        test_script_syntax
        test_function_structure
        test_error_handling
        test_color_output
        test_config_validation
        test_help_function
        test_invalid_options
        test_basic_dry_run
    )
    
    for test in "${tests[@]}"; do
        echo ""
        if $test; then
            tests_passed=$((tests_passed + 1))
        else
            tests_failed=$((tests_failed + 1))
        fi
    done
    
    # Cleanup
    cleanup_test_env
    
    # Summary
    echo ""
    echo "=================================================="
    echo -e "${COLOR_GREEN}Test Summary:${COLOR_RESET}"
    echo -e "Tests Passed: ${COLOR_GREEN}$tests_passed${COLOR_RESET}"
    echo -e "Tests Failed: ${COLOR_RED}$tests_failed${COLOR_RESET}"
    
    if [ $tests_failed -eq 0 ]; then
        log_success "All tests passed! The installer is ready for real testing."
        echo ""
        echo "Next steps for real testing:"
        echo "1. Place a real Greenplum installer RPM in the 'files/' directory"
        echo "2. Configure real hostnames in gpdb_config.conf"
        echo "3. Run: ./gpdb_installer.sh --dry-run"
        echo "4. Test on actual systems when ready"
    else
        log_error "Some tests failed. Please review the errors above."
        exit 1
    fi
}

# Run tests
main 