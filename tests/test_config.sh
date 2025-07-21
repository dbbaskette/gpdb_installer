#!/bin/bash

# Unit tests for config.sh library

source "$(dirname "${BASH_SOURCE[0]}")/test_framework.sh"
source "$LIB_DIR/config.sh"

# Test configuration loading
test_configuration_loading() {
    test_log "Testing configuration loading"
    
    # Create a test configuration file
    local test_config="$TEST_TEMP_DIR/test_config.conf"
    cat > "$test_config" << EOF
GPDB_COORDINATOR_HOST="test-coordinator"
GPDB_STANDBY_HOST="test-standby"
GPDB_SEGMENT_HOSTS=(test-segment1 test-segment2)
GPDB_INSTALL_DIR="/usr/local/greenplum"
GPDB_DATA_DIR="/data/primary"
EOF
    
    # Test loading valid configuration
    assert_command_succeeds "load_configuration '$test_config'" "Load valid configuration"
    
    # Verify configuration was loaded
    assert_equals "test-coordinator" "$GPDB_COORDINATOR_HOST" "Coordinator host loaded correctly"
    assert_equals "test-standby" "$GPDB_STANDBY_HOST" "Standby host loaded correctly"
    assert_equals "/usr/local/greenplum" "$GPDB_INSTALL_DIR" "Install directory loaded correctly"
    
    # Test loading non-existent configuration
    assert_command_fails "load_configuration '/nonexistent/config'" "Load non-existent configuration"
}

# Test configuration saving
test_configuration_saving() {
    test_log "Testing configuration saving"
    
    # Set up configuration variables
    GPDB_COORDINATOR_HOST="save-test-coordinator"
    GPDB_STANDBY_HOST="save-test-standby"
    GPDB_SEGMENT_HOSTS=("save-test-segment1" "save-test-segment2")
    GPDB_INSTALL_DIR="/usr/local/greenplum-save"
    GPDB_DATA_DIR="/data/primary-save"
    
    local test_config="$TEST_TEMP_DIR/save_test_config.conf"
    
    # Test saving configuration
    assert_command_succeeds "save_configuration '$test_config'" "Save configuration"
    
    # Verify file was created
    assert_file_exists "$test_config" "Configuration file created"
    
    # Verify content
    if [ -f "$test_config" ]; then
        grep -q "save-test-coordinator" "$test_config"
        assert_equals "0" "$?" "Coordinator host saved correctly"
        
        grep -q "save-test-standby" "$test_config"
        assert_equals "0" "$?" "Standby host saved correctly"
        
        grep -q "/usr/local/greenplum-save" "$test_config"
        assert_equals "0" "$?" "Install directory saved correctly"
    fi
}

# Test getting all hosts
test_get_all_hosts() {
    test_log "Testing get all hosts function"
    
    # Set up test configuration
    GPDB_COORDINATOR_HOST="coordinator"
    GPDB_SEGMENT_HOSTS=("segment1" "segment2" "coordinator")  # Include duplicate
    GPDB_STANDBY_HOST="standby"
    
    local all_hosts=($(get_all_hosts))
    
    # Should return unique hosts
    local expected_count=3  # coordinator, segment1, segment2, standby (coordinator duplicate removed)
    assert_equals "4" "${#all_hosts[@]}" "Correct number of unique hosts"
    
    # Verify all expected hosts are present
    local hosts_string=" ${all_hosts[*]} "
    [[ "$hosts_string" =~ " coordinator " ]] && test_success "Coordinator host included"
    [[ "$hosts_string" =~ " segment1 " ]] && test_success "Segment1 host included"
    [[ "$hosts_string" =~ " segment2 " ]] && test_success "Segment2 host included"
    [[ "$hosts_string" =~ " standby " ]] && test_success "Standby host included"
}

# Test single node detection
test_single_node_detection() {
    test_log "Testing single node installation detection"
    
    # Test single node configuration
    GPDB_COORDINATOR_HOST="single-node"
    GPDB_SEGMENT_HOSTS=("single-node")
    GPDB_STANDBY_HOST=""
    
    assert_command_succeeds "is_single_node_installation" "Single node detection - true case"
    
    # Test multi-node configuration
    GPDB_COORDINATOR_HOST="coordinator"
    GPDB_SEGMENT_HOSTS=("segment1" "segment2")
    GPDB_STANDBY_HOST=""
    
    assert_command_fails "is_single_node_installation" "Single node detection - false case"
}

# Test configuration display
test_configuration_display() {
    test_log "Testing configuration display"
    
    # Set up test configuration
    GPDB_COORDINATOR_HOST="display-coordinator"
    GPDB_SEGMENT_HOSTS=("display-segment1" "display-segment2")
    GPDB_STANDBY_HOST="display-standby"
    GPDB_INSTALL_DIR="/usr/local/greenplum-display"
    GPDB_DATA_DIR="/data/primary-display"
    
    # Test that show_configuration doesn't fail
    assert_command_succeeds "show_configuration >/dev/null" "Show configuration function"
}

# Test configuration validation completeness
test_configuration_validation_completeness() {
    test_log "Testing configuration validation completeness"
    
    # Set up complete configuration
    GPDB_COORDINATOR_HOST="complete-coordinator"
    GPDB_SEGMENT_HOSTS=("complete-segment1")
    GPDB_INSTALL_DIR="/usr/local/greenplum-complete"
    GPDB_DATA_DIR="/data/primary-complete"
    
    assert_command_succeeds "validate_configuration_completeness" "Complete configuration validation"
    
    # Test with missing coordinator
    unset GPDB_COORDINATOR_HOST
    assert_command_fails "validate_configuration_completeness" "Incomplete configuration validation"
}

# Test configuration export
test_configuration_export() {
    test_log "Testing configuration export"
    
    # Set up configuration
    GPDB_COORDINATOR_HOST="export-coordinator"
    GPDB_SEGMENT_HOSTS=("export-segment1")
    GPDB_INSTALL_DIR="/usr/local/greenplum-export"
    GPDB_DATA_DIR="/data/primary-export"
    
    # Test export (should not fail)
    assert_command_succeeds "export_configuration" "Export configuration"
}

# Test configuration reset
test_configuration_reset() {
    test_log "Testing configuration reset"
    
    # Set up configuration
    GPDB_COORDINATOR_HOST="reset-coordinator"
    GPDB_SEGMENT_HOSTS=("reset-segment1")
    GPDB_INSTALL_DIR="/usr/local/greenplum-reset"
    GPDB_DATA_DIR="/data/primary-reset"
    
    # Reset configuration
    reset_configuration
    
    # Verify reset
    assert_equals "" "$GPDB_COORDINATOR_HOST" "Coordinator host reset"
    assert_equals "" "$GPDB_STANDBY_HOST" "Standby host reset"
    assert_equals "0" "${#GPDB_SEGMENT_HOSTS[@]}" "Segment hosts reset"
    assert_equals "$DEFAULT_INSTALL_DIR" "$GPDB_INSTALL_DIR" "Install directory reset to default"
    assert_equals "$DEFAULT_DATA_DIR" "$GPDB_DATA_DIR" "Data directory reset to default"
}

# Test configuration file format validation
test_configuration_file_format() {
    test_log "Testing configuration file format validation"
    
    # Create a malformed configuration file
    local malformed_config="$TEST_TEMP_DIR/malformed_config.conf"
    cat > "$malformed_config" << EOF
GPDB_COORDINATOR_HOST="test-coordinator"
INVALID_SYNTAX_LINE
GPDB_SEGMENT_HOSTS=(test-segment1 test-segment2)
EOF
    
    # Test loading malformed configuration should fail
    assert_command_fails "load_configuration '$malformed_config'" "Load malformed configuration"
}

# Test default values
test_default_values() {
    test_log "Testing default configuration values"
    
    # Reset configuration
    reset_configuration
    
    # Check default values
    assert_equals "/usr/local/greenplum-db" "$GPDB_INSTALL_DIR" "Default install directory"
    assert_equals "/data/primary" "$GPDB_DATA_DIR" "Default data directory"
    assert_equals "" "$GPDB_COORDINATOR_HOST" "Default coordinator host"
    assert_equals "" "$GPDB_STANDBY_HOST" "Default standby host"
    assert_equals "0" "${#GPDB_SEGMENT_HOSTS[@]}" "Default segment hosts"
}

# Run all configuration tests
run_configuration_tests() {
    test_log "Running configuration library tests"
    
    test_configuration_loading
    test_configuration_saving
    test_get_all_hosts
    test_single_node_detection
    test_configuration_display
    test_configuration_validation_completeness
    test_configuration_export
    test_configuration_reset
    test_configuration_file_format
    test_default_values
    
    test_info "Configuration tests completed"
}

# Execute tests if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_configuration_tests
fi