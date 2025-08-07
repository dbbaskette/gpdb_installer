# Developer Guide

## Quick Start

### Running the Refactored Installer

```bash
# Basic installation
./gpdb_installer_v2.sh

# Dry run mode (test without making changes)
./gpdb_installer_v2.sh --dry-run

# Custom configuration file
./gpdb_installer_v2.sh --config my_config.conf

# Help
./gpdb_installer_v2.sh --help
```

### Running Tests

```bash
# Run all tests
./tests/run_all_tests.sh

# Run specific test
./tests/run_all_tests.sh test_config.sh

# Run with verbose output
./tests/run_all_tests.sh --verbose

# Run unit tests only
./tests/run_all_tests.sh --unit

# List available tests
./tests/run_all_tests.sh --list
```

## Development Setup

### Prerequisites

1. **Bash 4.0+** - Required for associative arrays
2. **Standard Unix tools** - grep, sed, awk, etc.
3. **Development tools** - For testing and development

### Development Environment

```bash
# Clone or navigate to project
cd gpdb_installer

# Make scripts executable
chmod +x lib/*.sh tests/*.sh *.sh

# Run tests to verify setup
./tests/run_all_tests.sh --quick
```

## Code Organization

### Library Structure

Each library module follows this pattern:

```bash
#!/bin/bash

# Library description and purpose
# Provides specific functionality for the installer

# Source dependencies
source "$(dirname "${BASH_SOURCE[0]}")/other_lib.sh"

# Public function with clear documentation
function_name() {
    local param1="$1"
    local param2="$2"
    
    # Implementation
    log_info "Descriptive message"
    
    # Error handling
    if ! some_operation; then
        log_error "Specific error message"
        return 1
    fi
    
    return 0
}
```

### Function Design Principles

1. **Single Responsibility**: Each function does one thing well
2. **Clear Parameters**: Well-defined input parameters
3. **Consistent Return Codes**: 0 for success, non-zero for failure
4. **Descriptive Names**: Function names clearly indicate purpose
5. **Error Handling**: Proper error detection and reporting

### Example Function

```bash
# Function to validate hostname format
validate_hostname() {
    local hostname="$1"
    
    # Input validation
    if [ -z "$hostname" ]; then
        log_error "Hostname cannot be empty"
        return 1
    fi
    
    # Format validation
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid hostname format: $hostname"
        return 1
    fi
    
    # Length validation
    if [ ${#hostname} -gt 253 ]; then
        log_error "Hostname too long: $hostname"
        return 1
    fi
    
    return 0
}
```

## Testing Framework

### Writing Tests

Tests follow the Arrange-Act-Assert pattern:

```bash
# Test function example
test_hostname_validation() {
    test_log "Testing hostname validation"
    
    # Arrange - Set up test data
    local valid_hostname="server1.example.com"
    local invalid_hostname="server_invalid"
    
    # Act & Assert - Test valid case
    assert_command_succeeds "validate_hostname '$valid_hostname'" "Valid hostname test"
    
    # Act & Assert - Test invalid case
    assert_command_fails "validate_hostname '$invalid_hostname'" "Invalid hostname test"
}
```

### Test Categories

1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test component interactions
3. **End-to-End Tests**: Test complete workflows
4. **Performance Tests**: Test operation timing

### Mock System

The test framework provides mocking capabilities:

```bash
# Mock external commands
mock_command "ssh" 0 "Success output"
mock_command "scp" 1 "Error output"

# Setup mock environment
setup_mock_ssh
setup_mock_system
```

### Assertions

Available assertion functions:

```bash
assert_equals "expected" "actual" "message"
assert_not_equals "expected" "actual" "message"
assert_true "condition" "message"
assert_false "condition" "message"
assert_file_exists "/path/to/file" "message"
assert_file_not_exists "/path/to/file" "message"
assert_command_succeeds "command" "message"
assert_command_fails "command" "message"
```

## Error Handling

### Error Handling Pattern

```bash
# Function with proper error handling
perform_operation() {
    local param="$1"
    
    # Validate input
    if [ -z "$param" ]; then
        log_error "Parameter required"
        return 1
    fi
    
    # Perform operation with error checking
    if ! some_command "$param"; then
        log_error "Operation failed for: $param"
        return 1
    fi
    
    # Log success
    log_success "Operation completed successfully"
    return 0
}
```

### Global Error Handler

The installer uses a global error handler:

```bash
# Automatic error handling
set -eE
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR

# Manual error handling when needed
if ! risky_operation; then
    handle_specific_error
    return 1
fi
```

### Cleanup Functions

Register cleanup functions for proper resource management:

```bash
# Register cleanup function
add_cleanup_function "cleanup_temp_files"

# Cleanup function implementation
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/installer_* 2>/dev/null || true
}
```

## Configuration Management

### Configuration Variables

Standard configuration variables:

```bash
# Required variables
GPDB_COORDINATOR_HOST="coordinator.example.com"
GPDB_SEGMENT_HOSTS=(segment1 segment2 segment3)
GPDB_INSTALL_DIR="/usr/local/greenplum-db"
GPDB_DATA_DIR="/data/primary"

# Optional variables
GPDB_STANDBY_HOST="standby.example.com"
```

### Configuration Functions

```bash
# Load configuration
load_configuration "config_file.conf"

# Save configuration
save_configuration "config_file.conf"

# Interactive configuration
configure_installation "config_file.conf"

# Validate configuration
validate_configuration
```

## SSH Operations

### SSH Best Practices

1. **Connection Reuse**: Use multiplexed connections
2. **Error Handling**: Proper timeout and retry logic
3. **Security**: Proper key permissions and host verification
4. **Cleanup**: Close connections and clean up sockets

### SSH Function Examples

```bash
# Execute remote command
ssh_execute "hostname" "remote_command"

# Copy file to remote host
ssh_copy_file "local_file" "hostname" "remote_path"

# Test SSH connectivity
test_ssh_connectivity "username" "hostname"
```

## Logging and Progress

### Logging Levels

```bash
log_info "Informational message"
log_success "Success message"
log_warn "Warning message"
log_error "Error message"  # Also exits with code 1
```

### Progress Reporting

```bash
# Phase reporting
report_phase_start 1 "Phase Name"
report_phase_complete "Phase Name"

# Step reporting
increment_step
report_progress "Phase Name" $CURRENT_STEP 5 "Step description"

# Progress bar
show_progress "Operation" 3 10  # 3 out of 10 complete
```

## Performance Considerations

### Timing Operations

```bash
# Measure operation time
start_timer
perform_operation
stop_timer

# Assert performance
assert_performance "5.0" "Operation should complete in under 5 seconds"
```

### Optimization Guidelines

1. **Minimize SSH Connections**: Use connection multiplexing
2. **Parallel Operations**: Run independent operations concurrently
3. **Efficient Commands**: Use appropriate tools for the task
4. **Resource Management**: Clean up resources promptly

## Debugging

### Debug Mode

```bash
# Enable debug mode
set -x

# Disable debug mode
set +x

# Debug specific function
bash -x ./lib/config.sh
```

### Troubleshooting

1. **Check Error Log**: `/tmp/gpdb_installer_errors.log`
2. **Verify Configuration**: Use `validate_configuration`
3. **Test SSH**: Use `test_ssh_connectivity`
4. **Check Resources**: Use `check_system_resources`

### Common Issues

1. **SSH Connection Failures**
   - Check SSH service running
   - Verify host connectivity
   - Check SSH key permissions

2. **Configuration Errors**
   - Validate hostname formats
   - Check directory paths
   - Verify user permissions

3. **Resource Issues**
   - Check memory availability
   - Verify disk space
   - Check network connectivity

## Code Style

### Naming Conventions

```bash
# Functions: lowercase with underscores
function_name() { ... }

# Variables: uppercase for global, lowercase for local
GLOBAL_VARIABLE="value"
local local_variable="value"

# Constants: uppercase with underscores
readonly CONSTANT_VALUE="value"
```

### Documentation

```bash
# Function documentation
# Function: function_name
# Description: Brief description of what the function does
# Parameters:
#   $1 - First parameter description
#   $2 - Second parameter description
# Returns:
#   0 - Success
#   1 - Error condition
# Example:
#   function_name "param1" "param2"
function_name() {
    local param1="$1"
    local param2="$2"
    
    # Implementation
}
```

## Contributing

### Pull Request Process

1. **Fork and Branch**: Create feature branch
2. **Implement Changes**: Follow coding standards
3. **Add Tests**: Ensure test coverage
4. **Update Documentation**: Keep docs current
5. **Test Thoroughly**: Run full test suite
6. **Submit PR**: Include clear description

### Code Review Checklist

- [ ] Functions are single-purpose and well-named
- [ ] Error handling is comprehensive
- [ ] Tests cover new functionality
- [ ] Documentation is updated
- [ ] Performance impact is considered
- [ ] Security implications are addressed

## Release Process

### Version Management

1. **Update Version**: In main script and documentation
2. **Update Changelog**: Document changes
3. **Test Release**: Full test suite on multiple platforms
4. **Tag Release**: Create git tag
5. **Deploy**: Update distribution packages

### Testing Before Release

```bash
# Run comprehensive tests
./tests/run_all_tests.sh --verbose

# Test on different OS versions
./tests/run_all_tests.sh --integration

# Performance testing
./tests/run_all_tests.sh --coverage
```

## Troubleshooting Development Issues

### Common Development Problems

1. **Library Loading Issues**
   - Check file paths in source statements
   - Verify script permissions
   - Check for syntax errors

2. **Test Failures**
   - Verify mock setup
   - Check test environment
   - Review assertion logic

3. **SSH Issues in Development**
   - Use mock SSH for unit tests
   - Test with actual SSH for integration
   - Check SSH key setup

### Getting Help

1. **Review Architecture**: Check ARCHITECTURE.md
2. **Check Examples**: Look at existing code patterns
3. **Run Tests**: Use test framework for validation
4. **Check Logs**: Review error logs and debug output