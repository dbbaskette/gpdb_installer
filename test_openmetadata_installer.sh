#!/bin/bash

# OpenMetadata Installer Test Script
# Tests the OpenMetadata installer functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER_SCRIPT="$SCRIPT_DIR/openmetadata_installer.sh"
CONFIG_TEMPLATE="$SCRIPT_DIR/openmetadata_config.conf.template"
TEST_CONFIG="$SCRIPT_DIR/test_openmetadata_config.conf"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message"
            ((TESTS_FAILED++))
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
    esac
}

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_exit_code="${3:-0}"
    
    print_status "INFO" "Running test: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        local exit_code=$?
        if [[ $exit_code -eq $expected_exit_code ]]; then
            print_status "PASS" "$test_name"
        else
            print_status "FAIL" "$test_name (expected exit code $expected_exit_code, got $exit_code)"
        fi
    else
        local exit_code=$?
        if [[ $exit_code -eq $expected_exit_code ]]; then
            print_status "PASS" "$test_name"
        else
            print_status "FAIL" "$test_name (expected exit code $expected_exit_code, got $exit_code)"
        fi
    fi
}

# Function to check if file exists
check_file_exists() {
    local file="$1"
    local test_name="$2"
    
    if [[ -f "$file" ]]; then
        print_status "PASS" "$test_name"
    else
        print_status "FAIL" "$test_name"
    fi
}

# Function to check if script is executable
check_executable() {
    local file="$1"
    local test_name="$2"
    
    if [[ -x "$file" ]]; then
        print_status "PASS" "$test_name"
    else
        print_status "FAIL" "$test_name"
    fi
}

# Function to test help functionality
test_help() {
    local output
    output=$("$INSTALLER_SCRIPT" --help 2>&1)
    
    if echo "$output" | grep -q "Usage:"; then
        print_status "PASS" "Help functionality works"
    else
        print_status "FAIL" "Help functionality failed"
    fi
}

# Function to test version functionality
test_version() {
    local output
    output=$("$INSTALLER_SCRIPT" --version 2>&1)
    
    if echo "$output" | grep -q "OpenMetadata Installer"; then
        print_status "PASS" "Version functionality works"
    else
        print_status "FAIL" "Version functionality failed"
    fi
}

# Function to test dry run mode
test_dry_run() {
    # Create a test config file
    cp "$CONFIG_TEMPLATE" "$TEST_CONFIG"
    
    # Modify test config for dry run
    sed -i 's/openmetadata-server.example.com/localhost/g' "$TEST_CONFIG"
    sed -i 's/admin@example.com/test@example.com/g' "$TEST_CONFIG"
    sed -i 's/your-secure-admin-password-here/test-password-123/g' "$TEST_CONFIG"
    
    local output
    output=$("$INSTALLER_SCRIPT" --config "$TEST_CONFIG" --dry-run 2>&1)
    
    if echo "$output" | grep -q "Dry run mode enabled"; then
        print_status "PASS" "Dry run mode works"
    else
        print_status "FAIL" "Dry run mode failed"
    fi
    
    # Clean up test config
    rm -f "$TEST_CONFIG"
}

# Function to test configuration validation
test_config_validation() {
    # Test with missing config file
    local output
    output=$("$INSTALLER_SCRIPT" --config "nonexistent.conf" 2>&1)
    
    if echo "$output" | grep -q "not found"; then
        print_status "PASS" "Configuration validation works (missing file)"
    else
        print_status "FAIL" "Configuration validation failed (missing file)"
    fi
}

# Function to test Docker detection
test_docker_detection() {
    # This test checks if the script can detect Docker installation
    # We'll just verify the script doesn't crash when checking for Docker
    local output
    output=$("$INSTALLER_SCRIPT" --config "$CONFIG_TEMPLATE" --dry-run 2>&1)
    
    if echo "$output" | grep -q "Docker"; then
        print_status "PASS" "Docker detection works"
    else
        print_status "WARN" "Docker detection may not be working properly"
    fi
}

# Function to test port availability check
test_port_check() {
    # Test if the script can check port availability
    local output
    output=$("$INSTALLER_SCRIPT" --config "$CONFIG_TEMPLATE" --dry-run 2>&1)
    
    if echo "$output" | grep -q "Port.*Available\|Port.*in use"; then
        print_status "PASS" "Port availability check works"
    else
        print_status "WARN" "Port availability check may not be working"
    fi
}

# Function to test system requirements check
test_system_requirements() {
    local output
    output=$("$INSTALLER_SCRIPT" --config "$CONFIG_TEMPLATE" --dry-run 2>&1)
    
    if echo "$output" | grep -q "Memory\|Disk space\|OS Information"; then
        print_status "PASS" "System requirements check works"
    else
        print_status "WARN" "System requirements check may not be working"
    fi
}

# Function to test network connectivity check
test_network_check() {
    local output
    output=$("$INSTALLER_SCRIPT" --config "$CONFIG_TEMPLATE" --dry-run 2>&1)
    
    if echo "$output" | grep -q "connectivity\|Docker Hub\|GitHub"; then
        print_status "PASS" "Network connectivity check works"
    else
        print_status "WARN" "Network connectivity check may not be working"
    fi
}

# Function to test Docker Compose file generation
test_docker_compose_generation() {
    # Create a test config file
    cp "$CONFIG_TEMPLATE" "$TEST_CONFIG"
    
    # Modify test config
    sed -i 's/openmetadata-server.example.com/localhost/g' "$TEST_CONFIG"
    sed -i 's/admin@example.com/test@example.com/g' "$TEST_CONFIG"
    sed -i 's/your-secure-admin-password-here/test-password-123/g' "$TEST_CONFIG"
    
    # Run dry run to generate Docker Compose file
    "$INSTALLER_SCRIPT" --config "$TEST_CONFIG" --dry-run >/dev/null 2>&1
    
    if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        print_status "PASS" "Docker Compose file generation works"
        # Clean up generated file
        rm -f "$SCRIPT_DIR/docker-compose.yml"
    else
        print_status "FAIL" "Docker Compose file generation failed"
    fi
    
    # Clean up test config
    rm -f "$TEST_CONFIG"
}

# Function to test MCP server setup
test_mcp_server_setup() {
    # Create a test config file with MCP enabled
    cp "$CONFIG_TEMPLATE" "$TEST_CONFIG"
    
    # Modify test config
    sed -i 's/openmetadata-server.example.com/localhost/g' "$TEST_CONFIG"
    sed -i 's/admin@example.com/test@example.com/g' "$TEST_CONFIG"
    sed -i 's/your-secure-admin-password-here/test-password-123/g' "$TEST_CONFIG"
    sed -i 's/MCP_SERVER_ENABLED=true/MCP_SERVER_ENABLED=true/g' "$TEST_CONFIG"
    
    # Run dry run to test MCP server setup
    local output
    output=$("$INSTALLER_SCRIPT" --config "$TEST_CONFIG" --dry-run 2>&1)
    
    if echo "$output" | grep -q "MCP Server"; then
        print_status "PASS" "MCP server setup works"
    else
        print_status "WARN" "MCP server setup may not be working"
    fi
    
    # Clean up test config
    rm -f "$TEST_CONFIG"
}

# Function to test service script generation
test_service_script_generation() {
    # Create a test config file
    cp "$CONFIG_TEMPLATE" "$TEST_CONFIG"
    
    # Modify test config
    sed -i 's/openmetadata-server.example.com/localhost/g' "$TEST_CONFIG"
    sed -i 's/admin@example.com/test@example.com/g' "$TEST_CONFIG"
    sed -i 's/your-secure-admin-password-here/test-password-123/g' "$TEST_CONFIG"
    
    # Run dry run to generate service scripts
    "$INSTALLER_SCRIPT" --config "$TEST_CONFIG" --dry-run >/dev/null 2>&1
    
    local scripts_created=0
    if [[ -f "$SCRIPT_DIR/start_openmetadata.sh" ]]; then ((scripts_created++)); fi
    if [[ -f "$SCRIPT_DIR/stop_openmetadata.sh" ]]; then ((scripts_created++)); fi
    if [[ -f "$SCRIPT_DIR/status_openmetadata.sh" ]]; then ((scripts_created++)); fi
    
    if [[ $scripts_created -eq 3 ]]; then
        print_status "PASS" "Service script generation works"
        # Clean up generated scripts
        rm -f "$SCRIPT_DIR"/{start,stop,status}_openmetadata.sh
    else
        print_status "FAIL" "Service script generation failed ($scripts_created/3 scripts created)"
    fi
    
    # Clean up test config
    rm -f "$TEST_CONFIG"
}

# Function to test clean mode
test_clean_mode() {
    local output
    output=$("$INSTALLER_SCRIPT" --clean --dry-run 2>&1)
    
    if echo "$output" | grep -q "clean"; then
        print_status "PASS" "Clean mode works"
    else
        print_status "FAIL" "Clean mode failed"
    fi
}

# Function to test invalid arguments
test_invalid_arguments() {
    local output
    output=$("$INSTALLER_SCRIPT" --invalid-option 2>&1)
    
    if echo "$output" | grep -q "Unknown option\|help"; then
        print_status "PASS" "Invalid argument handling works"
    else
        print_status "FAIL" "Invalid argument handling failed"
    fi
}

# Function to test configuration template
test_config_template() {
    if [[ -f "$CONFIG_TEMPLATE" ]]; then
        # Check if template contains required variables
        local required_vars=(
            "OPENMETADATA_HOST"
            "OPENMETADATA_VERSION"
            "OPENMETADATA_ADMIN_EMAIL"
            "OPENMETADATA_ADMIN_PASSWORD"
            "MCP_SERVER_ENABLED"
        )
        
        local missing_vars=0
        for var in "${required_vars[@]}"; do
            if ! grep -q "$var" "$CONFIG_TEMPLATE"; then
                ((missing_vars++))
            fi
        done
        
        if [[ $missing_vars -eq 0 ]]; then
            print_status "PASS" "Configuration template is complete"
        else
            print_status "FAIL" "Configuration template missing $missing_vars required variables"
        fi
    else
        print_status "FAIL" "Configuration template file not found"
    fi
}

# Function to run all tests
run_all_tests() {
    echo "=== OpenMetadata Installer Test Suite ==="
    echo "Testing installer: $INSTALLER_SCRIPT"
    echo "Test started at: $(date)"
    echo
    
    # Basic file checks
    check_file_exists "$INSTALLER_SCRIPT" "Installer script exists"
    check_executable "$INSTALLER_SCRIPT" "Installer script is executable"
    check_file_exists "$CONFIG_TEMPLATE" "Configuration template exists"
    
    # Basic functionality tests
    test_help
    test_version
    test_invalid_arguments
    
    # Configuration tests
    test_config_template
    test_config_validation
    
    # System checks
    test_system_requirements
    test_network_check
    test_port_check
    test_docker_detection
    
    # Installation tests
    test_dry_run
    test_docker_compose_generation
    test_mcp_server_setup
    test_service_script_generation
    test_clean_mode
    
    echo
    echo "=== Test Summary ==="
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_all_tests
fi 