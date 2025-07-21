#!/bin/bash

# Unit tests for validation.sh library

source "$(dirname "${BASH_SOURCE[0]}")/test_framework.sh"
source "$LIB_DIR/validation.sh"

# Test hostname validation
test_hostname_validation() {
    test_log "Testing hostname validation"
    
    # Valid hostnames
    assert_command_succeeds "validate_hostname 'localhost'" "Valid hostname: localhost"
    assert_command_succeeds "validate_hostname 'server1'" "Valid hostname: server1"
    assert_command_succeeds "validate_hostname 'server-1.example.com'" "Valid hostname with domain"
    
    # Invalid hostnames
    assert_command_fails "validate_hostname 'server_invalid'" "Invalid hostname with underscore"
    assert_command_fails "validate_hostname ''" "Empty hostname"
    
    # Test very long hostname
    local long_hostname=$(printf 'a%.0s' {1..300})
    assert_command_fails "validate_hostname '$long_hostname'" "Hostname too long"
}

# Test directory path validation
test_directory_path_validation() {
    test_log "Testing directory path validation"
    
    # Valid paths
    assert_command_succeeds "validate_directory_path '/usr/local/greenplum' 'test'" "Valid absolute path"
    assert_command_succeeds "validate_directory_path '/data/primary' 'test'" "Valid data directory path"
    
    # Invalid paths
    assert_command_fails "validate_directory_path 'relative/path' 'test'" "Invalid relative path"
    assert_command_fails "validate_directory_path '/path with spaces' 'test'" "Invalid path with spaces"
    
    # Test very long path
    local long_path="/$(printf 'a%.0s' {1..5000})"
    assert_command_fails "validate_directory_path '$long_path' 'test'" "Path too long"
}

# Test password validation
test_password_validation() {
    test_log "Testing password validation"
    
    # Mock user input for continuing with weak password
    echo "y" | validate_password "weak" "test" >/dev/null 2>&1
    local result=$?
    assert_equals "0" "$result" "Weak password accepted with confirmation"
    
    # Strong password should pass without prompting
    validate_password "strongpassword123" "test" >/dev/null 2>&1
    result=$?
    assert_equals "0" "$result" "Strong password accepted"
}

# Test sudo privileges check
test_sudo_privileges_check() {
    test_log "Testing sudo privileges check"
    
    # Mock sudo command
    mock_command "sudo" 0 ""
    
    assert_command_succeeds "check_sudo_privileges" "Sudo privileges check with mock"
}

# Test network connectivity validation
test_network_connectivity_validation() {
    test_log "Testing network connectivity validation"
    
    # Mock ping command
    mock_command "ping" 0 "PING localhost"
    
    assert_command_succeeds "validate_network_connectivity 'localhost' 5" "Network connectivity test with mock"
    
    # Mock failed ping
    mock_command "ping" 1 ""
    
    assert_command_fails "validate_network_connectivity 'nonexistent' 5" "Network connectivity test failure"
}

# Test SSH connectivity validation
test_ssh_connectivity_validation() {
    test_log "Testing SSH connectivity validation"
    
    # Mock SSH command
    mock_command "ssh" 0 "SSH test"
    
    assert_command_succeeds "validate_ssh_connectivity 'localhost' 5" "SSH connectivity test with mock"
    
    # Mock failed SSH
    mock_command "ssh" 1 ""
    
    assert_command_fails "validate_ssh_connectivity 'nonexistent' 5" "SSH connectivity test failure"
}

# Test file access validation
test_file_access_validation() {
    test_log "Testing file access validation"
    
    # Create test files
    local test_file="$TEST_TEMP_DIR/test_file.txt"
    echo "test content" > "$test_file"
    chmod 644 "$test_file"
    
    assert_command_succeeds "validate_file_access '$test_file' 'r'" "File read access validation"
    
    # Test non-existent file
    assert_command_fails "validate_file_access '/nonexistent/file' 'r'" "Non-existent file validation"
    
    # Test write access
    chmod 644 "$test_file"
    assert_command_succeeds "validate_file_access '$test_file' 'w'" "File write access validation"
}

# Test system requirements validation
test_system_requirements_validation() {
    test_log "Testing system requirements validation"
    
    # Mock system files
    mkdir -p "$TEST_TEMP_DIR/proc"
    echo "MemTotal: 16777216 kB" > "$TEST_TEMP_DIR/proc/meminfo"
    
    # Mock df command
    mock_command "df" 0 "Filesystem 1K-blocks Used Available Use% Mounted on
/dev/sda1 20971520 10485760 10485760 50% /"
    
    # Test with sufficient resources
    GPDB_DATA_DIR="$TEST_TEMP_DIR"
    assert_command_succeeds "validate_system_requirements 8 10" "System requirements with sufficient resources"
    
    # Test with insufficient memory
    echo "MemTotal: 4194304 kB" > "$TEST_TEMP_DIR/proc/meminfo"
    assert_command_fails "validate_system_requirements 8 10" "System requirements with insufficient memory"
}

# Test configuration validation
test_configuration_validation() {
    test_log "Testing configuration validation"
    
    # Set up valid configuration
    GPDB_COORDINATOR_HOST="test-coordinator"
    GPDB_SEGMENT_HOSTS=("test-segment1" "test-segment2")
    GPDB_INSTALL_DIR="/usr/local/greenplum"
    GPDB_DATA_DIR="/data/primary"
    
    assert_command_succeeds "validate_configuration" "Valid configuration"
    
    # Test with missing coordinator
    unset GPDB_COORDINATOR_HOST
    assert_command_fails "validate_configuration" "Configuration missing coordinator"
    
    # Reset for next test
    GPDB_COORDINATOR_HOST="test-coordinator"
    
    # Test with empty segment hosts
    GPDB_SEGMENT_HOSTS=()
    assert_command_fails "validate_configuration" "Configuration with empty segment hosts"
}

# Run all validation tests
run_validation_tests() {
    test_log "Running validation library tests"
    
    test_hostname_validation
    test_directory_path_validation
    test_password_validation
    test_sudo_privileges_check
    test_network_connectivity_validation
    test_ssh_connectivity_validation
    test_file_access_validation
    test_system_requirements_validation
    test_configuration_validation
    
    test_info "Validation tests completed"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_validation_tests
fi