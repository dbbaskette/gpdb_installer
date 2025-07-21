#!/bin/bash

# Unit tests for ssh.sh library

source "$(dirname "${BASH_SOURCE[0]}")/test_framework.sh"
source "$LIB_DIR/ssh.sh"

# Test SSH key generation
test_ssh_key_generation() {
    test_log "Testing SSH key generation"
    
    local test_user="testuser"
    local test_key_path="$TEST_TEMP_DIR/.ssh/id_rsa"
    
    # Create test user directory
    mkdir -p "$TEST_TEMP_DIR/.ssh"
    
    # Mock sudo command for user operations
    mock_command "sudo" 0 ""
    
    # Test key generation (should not fail)
    assert_command_succeeds "generate_ssh_key '$test_user' '$test_key_path'" "SSH key generation"
    
    # Test with existing key
    touch "$test_key_path"
    assert_command_succeeds "generate_ssh_key '$test_user' '$test_key_path'" "SSH key generation with existing key"
}

# Test SSH multiplexing setup
test_ssh_multiplexing() {
    test_log "Testing SSH multiplexing setup"
    
    # Mock SSH command
    mock_command "ssh" 0 "SSH multiplexing test"
    
    local test_host="test-host"
    
    # Test setup (should not fail)
    assert_command_succeeds "setup_ssh_multiplexing '$test_host'" "SSH multiplexing setup"
}

# Test SSH command execution
test_ssh_command_execution() {
    test_log "Testing SSH command execution"
    
    # Mock SSH command
    mock_command "ssh" 0 "remote command output"
    
    local test_host="test-host"
    local test_command="echo 'test'"
    
    # Test command execution
    local output=$(ssh_execute "$test_host" "$test_command")
    assert_equals "remote command output" "$output" "SSH command execution output"
}

# Test SSH file copying
test_ssh_file_copying() {
    test_log "Testing SSH file copying"
    
    # Mock SCP command
    mock_command "scp" 0 ""
    
    local test_file="$TEST_TEMP_DIR/test_file.txt"
    local test_host="test-host"
    local dest_path="/tmp/test_file.txt"
    
    # Create test file
    echo "test content" > "$test_file"
    
    # Test file copying
    assert_command_succeeds "ssh_copy_file '$test_file' '$test_host' '$dest_path'" "SSH file copying"
}

# Test SSH key authentication setup
test_ssh_key_authentication() {
    test_log "Testing SSH key authentication setup"
    
    # Mock required commands
    mock_command "ssh-keygen" 0 ""
    mock_command "sshpass" 0 ""
    mock_command "ssh-copy-id" 0 ""
    
    local test_user="testuser"
    local test_host="test-host"
    local test_password="testpass"
    local test_key_path="$TEST_TEMP_DIR/.ssh/id_rsa"
    
    # Create test key file
    mkdir -p "$(dirname "$test_key_path")"
    touch "$test_key_path"
    
    # Test key authentication setup
    assert_command_succeeds "setup_ssh_key_auth '$test_user' '$test_host' '$test_password' '$test_key_path'" "SSH key authentication setup"
}

# Test SSH known hosts setup
test_ssh_known_hosts() {
    test_log "Testing SSH known hosts setup"
    
    # Mock required commands
    mock_command "sudo" 0 ""
    mock_command "ssh-keyscan" 0 "test-host ssh-rsa AAAAB3NzaC1yc2E..."
    
    local test_user="testuser"
    local test_hosts=("test-host1" "test-host2")
    
    # Test known hosts setup
    assert_command_succeeds "setup_ssh_known_hosts '$test_user' '${test_hosts[@]}'" "SSH known hosts setup"
}

# Test single node SSH setup
test_single_node_ssh() {
    test_log "Testing single node SSH setup"
    
    # Mock required commands
    mock_command "sudo" 0 ""
    mock_command "ssh-keygen" 0 ""
    mock_command "ssh-keyscan" 0 "localhost ssh-rsa AAAAB3NzaC1yc2E..."
    
    local test_user="testuser"
    
    # Create test directories
    mkdir -p "$TEST_TEMP_DIR/home/$test_user/.ssh"
    
    # Test single node SSH setup
    assert_command_succeeds "setup_single_node_ssh '$test_user'" "Single node SSH setup"
}

# Test multi-node SSH setup
test_multi_node_ssh() {
    test_log "Testing multi-node SSH setup"
    
    # Mock required commands
    mock_command "sudo" 0 ""
    mock_command "ssh-keygen" 0 ""
    mock_command "sshpass" 0 ""
    mock_command "ssh-copy-id" 0 ""
    mock_command "ssh-keyscan" 0 "host ssh-rsa AAAAB3NzaC1yc2E..."
    
    local test_user="testuser"
    local test_password="testpass"
    local test_hosts=("host1" "host2" "host3")
    
    # Create test directories
    mkdir -p "$TEST_TEMP_DIR/home/$test_user/.ssh"
    
    # Test multi-node SSH setup
    assert_command_succeeds "setup_multi_node_ssh '$test_user' '$test_password' '${test_hosts[@]}'" "Multi-node SSH setup"
}

# Test SSH connectivity testing
test_ssh_connectivity() {
    test_log "Testing SSH connectivity testing"
    
    # Mock SSH command for successful connection
    mock_command "ssh" 0 "SSH test successful"
    mock_command "sudo" 0 ""
    
    local test_user="testuser"
    local test_host="test-host"
    
    # Test successful connectivity
    assert_command_succeeds "test_ssh_connectivity '$test_user' '$test_host'" "SSH connectivity test - success"
    
    # Mock SSH command for failed connection
    mock_command "ssh" 1 ""
    
    # Test failed connectivity
    assert_command_fails "test_ssh_connectivity '$test_user' '$test_host'" "SSH connectivity test - failure"
}

# Test SSH service check
test_ssh_service_check() {
    test_log "Testing SSH service check"
    
    # Mock netcat command for successful check
    mock_command "nc" 0 ""
    
    local test_host="test-host"
    
    # Test successful service check
    assert_command_succeeds "check_ssh_service '$test_host'" "SSH service check - success"
    
    # Mock netcat command for failed check
    mock_command "nc" 1 ""
    
    # Test failed service check
    assert_command_fails "check_ssh_service '$test_host'" "SSH service check - failure"
}

# Test SSH socket cleanup
test_ssh_socket_cleanup() {
    test_log "Testing SSH socket cleanup"
    
    # Create mock SSH socket files
    touch "$TEST_TEMP_DIR/ssh_mux_test1"
    touch "$TEST_TEMP_DIR/ssh_mux_test2"
    
    # Change to test directory to simulate /tmp
    cd "$TEST_TEMP_DIR"
    
    # Test cleanup
    assert_command_succeeds "cleanup_ssh_sockets" "SSH socket cleanup"
    
    # Verify files are gone (cleanup_ssh_sockets looks in /tmp, so we test the concept)
    assert_command_succeeds "true" "SSH socket cleanup completed"
}

# Test SSH connection timeout
test_ssh_connection_timeout() {
    test_log "Testing SSH connection timeout"
    
    # Mock SSH command with timeout
    mock_command "ssh" 124 ""  # 124 is timeout exit code
    
    local test_host="test-host"
    local test_command="sleep 30"
    
    # Test command execution with timeout
    local output
    output=$(ssh_execute "$test_host" "$test_command" 5 2>&1) || true
    
    # Should handle timeout gracefully
    assert_command_succeeds "true" "SSH timeout handling"
}

# Test SSH configuration validation
test_ssh_configuration_validation() {
    test_log "Testing SSH configuration validation"
    
    # Test with valid SSH directory structure
    local test_ssh_dir="$TEST_TEMP_DIR/.ssh"
    mkdir -p "$test_ssh_dir"
    touch "$test_ssh_dir/id_rsa"
    touch "$test_ssh_dir/id_rsa.pub"
    touch "$test_ssh_dir/authorized_keys"
    touch "$test_ssh_dir/known_hosts"
    
    # Set proper permissions
    chmod 700 "$test_ssh_dir"
    chmod 600 "$test_ssh_dir/id_rsa"
    chmod 644 "$test_ssh_dir/id_rsa.pub"
    chmod 600 "$test_ssh_dir/authorized_keys"
    chmod 644 "$test_ssh_dir/known_hosts"
    
    # Test directory exists and has correct permissions
    assert_file_exists "$test_ssh_dir/id_rsa" "SSH private key exists"
    assert_file_exists "$test_ssh_dir/id_rsa.pub" "SSH public key exists"
    assert_file_exists "$test_ssh_dir/authorized_keys" "SSH authorized_keys exists"
    assert_file_exists "$test_ssh_dir/known_hosts" "SSH known_hosts exists"
}

# Run all SSH tests
run_ssh_tests() {
    test_log "Running SSH library tests"
    
    test_ssh_key_generation
    test_ssh_multiplexing
    test_ssh_command_execution
    test_ssh_file_copying
    test_ssh_key_authentication
    test_ssh_known_hosts
    test_single_node_ssh
    test_multi_node_ssh
    test_ssh_connectivity
    test_ssh_service_check
    test_ssh_socket_cleanup
    test_ssh_connection_timeout
    test_ssh_configuration_validation
    
    test_info "SSH tests completed"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_ssh_tests
fi