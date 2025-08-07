ls# Greenplum Installer Architecture

## Overview

The Greenplum Installer has been refactored into a modular, maintainable architecture with clear separation of concerns. This document describes the architectural decisions and component structure.

## Directory Structure

```
gpdb_installer/
├── lib/                          # Core library modules
│   ├── config.sh                 # Configuration management
│   ├── error_handling.sh         # Error handling and recovery
│   ├── greenplum.sh              # Greenplum-specific operations
│   ├── logging.sh                # Logging and progress reporting
│   ├── ssh.sh                    # SSH operations and connectivity
│   ├── system.sh                 # System checks and resource validation
│   └── validation.sh             # Input validation and prerequisites
├── tests/                        # Comprehensive test suite
│   ├── test_framework.sh         # Test framework and utilities
│   ├── test_config.sh            # Configuration module tests
│   ├── test_ssh.sh               # SSH module tests
│   ├── test_validation.sh        # Validation module tests
│   └── run_all_tests.sh          # Test runner and reporting
├── gpdb_installer.sh             # Original installer (legacy)
├── gpdb_installer_v2.sh          # New refactored installer
├── files/                        # Greenplum installation files
└── docs/                         # Documentation

```

## Core Principles

### 1. Separation of Concerns
Each library module has a single, well-defined responsibility:
- **config.sh**: Configuration management and user interaction
- **validation.sh**: Input validation and system checks
- **ssh.sh**: SSH operations and connection management
- **system.sh**: System resource checks and OS compatibility
- **greenplum.sh**: Greenplum-specific installation operations
- **logging.sh**: Logging, progress reporting, and user feedback
- **error_handling.sh**: Error recovery and cleanup

### 2. Modular Design
- Functions are small and focused (typically 10-30 lines)
- Related functionality is grouped into logical modules
- Clear interfaces between modules
- Reusable components across different installation scenarios

### 3. Robust Error Handling
- Comprehensive error detection and reporting
- Graceful error recovery mechanisms
- Cleanup functions for partial installations
- User-friendly error messages with actionable guidance

### 4. Testability
- Each module can be tested independently
- Mock functions for external dependencies
- Comprehensive test coverage for all functionality
- Performance testing for critical operations

## Component Architecture

### Configuration Management (config.sh)
```bash
# Key Functions:
- load_configuration()         # Load config from file
- save_configuration()         # Save config to file
- configure_installation()     # Interactive configuration
- validate_configuration()     # Validate config completeness
- get_all_hosts()             # Get unique list of all hosts
- is_single_node_installation() # Detect single-node setup
```

### Validation Framework (validation.sh)
```bash
# Key Functions:
- validate_hostname()          # Hostname format validation
- validate_directory_path()    # Directory path validation
- validate_password()          # Password strength validation
- validate_network_connectivity() # Network connectivity checks
- validate_ssh_connectivity()  # SSH connectivity validation
- validate_system_requirements() # System resource validation
```

### SSH Management (ssh.sh)
```bash
# Key Functions:
- setup_ssh_multiplexing()     # Enable SSH connection reuse
- ssh_execute()               # Execute remote commands
- ssh_copy_file()             # Copy files to remote hosts
- generate_ssh_key()          # Generate SSH key pairs
- setup_single_node_ssh()     # Configure localhost SSH
- setup_multi_node_ssh()      # Configure multi-host SSH
- test_ssh_connectivity()     # Test SSH connections
```

### System Operations (system.sh)
```bash
# Key Functions:
- check_os_compatibility()     # OS version compatibility
- check_system_resources()     # Memory and disk space
- check_dependencies()         # Required package availability
- check_network_connectivity() # Network connectivity between hosts
- install_sshpass()           # Install missing dependencies
```

### Greenplum Operations (greenplum.sh)
```bash
# Key Functions:
- find_greenplum_installer()   # Locate installer files
- distribute_installer()       # Copy installer to hosts
- install_greenplum_single()   # Install on single host
- generate_gpinitsystem_config() # Create cluster config
- initialize_greenplum_cluster() # Initialize cluster
- setup_gpadmin_environment()  # Configure environment
```

### Logging and Progress (logging.sh)
```bash
# Key Functions:
- log_info(), log_success(), log_warn(), log_error()
- log_*_with_timestamp()      # Timestamped logging
- show_progress()             # Progress bars
- report_phase_start()        # Phase reporting
- report_phase_complete()     # Phase completion
```

### Error Handling (error_handling.sh)
```bash
# Key Functions:
- handle_error()              # Global error handler
- execute_with_retry()        # Retry failed operations
- execute_with_timeout()      # Timeout protection
- create_backup()             # Backup before destructive ops
- cleanup_on_error()          # Error cleanup
```

## Installation Flow

### Phase 1: Initialization
1. Parse command line arguments
2. Setup signal handlers and error handling
3. Load or create configuration
4. Validate configuration completeness

### Phase 2: Pre-flight Checks
1. Check sudo privileges
2. Verify OS compatibility on all hosts
3. Check required dependencies
4. Validate system resources (memory, disk)
5. Check Greenplum version compatibility
6. Test network connectivity

### Phase 3: Host Setup
1. Collect user credentials
2. Create gpadmin user on all hosts
3. Create required directories
4. Setup SSH key authentication
5. Test SSH connectivity

### Phase 4: Greenplum Installation
1. Find and validate installer files
2. Distribute installer to all hosts
3. Install Greenplum binaries
4. Generate cluster configuration
5. Initialize cluster with gpinitsystem
6. Configure environment and pg_hba.conf

### Phase 5: Completion
1. Test cluster connectivity
2. Provide user instructions
3. Cleanup temporary files

## Error Recovery

### Cleanup Functions
- SSH socket cleanup
- Temporary file cleanup
- Partial installation cleanup
- User and directory cleanup

### Rollback Mechanisms
- Backup creation before destructive operations
- Restore from backup on failure
- Graceful handling of partial installations

### User Interruption
- Ctrl+C handling with cleanup options
- Signal handlers for graceful shutdown
- Progress preservation for resume capability

## Testing Strategy

### Unit Tests
- Test individual functions in isolation
- Mock external dependencies
- Validate input/output behavior
- Test error conditions

### Integration Tests
- Test component interactions
- End-to-end workflow testing
- Multi-host scenario testing
- Performance testing

### Test Framework Features
- Assertion functions for common checks
- Mock system for external commands
- Test environment setup/teardown
- Performance timing and reporting

## Configuration

### Configuration File Format
```bash
# Example gpdb_config.conf
GPDB_COORDINATOR_HOST="coordinator.example.com"
GPDB_STANDBY_HOST="standby.example.com"
GPDB_SEGMENT_HOSTS=(segment1 segment2 segment3)
GPDB_INSTALL_DIR="/usr/local/greenplum-db"
GPDB_DATA_DIR="/data/primary"
```

### Environment Variables
- `DRY_RUN`: Enable dry-run mode
- `TEST_TEMP_DIR`: Test temporary directory
- `GPDB_*`: Configuration variables

## Performance Considerations

### SSH Connection Reuse
- Multiplexed SSH connections reduce overhead
- Persistent connections for multiple operations
- Automatic cleanup of connection sockets

### Parallel Operations
- Concurrent operations where possible
- Progress reporting for long-running tasks
- Timeout protection for all operations

### Resource Management
- Memory and disk space validation
- Cleanup of temporary files
- Efficient handling of large files

## Security Considerations

### Password Handling
- Secure password collection (no echo)
- Password validation and strength checking
- No password storage in logs or files

### SSH Security
- Proper SSH key permissions (600/700)
- Host key verification
- Secure key distribution

### File Permissions
- Proper ownership and permissions
- Secure temporary file handling
- Cleanup of sensitive temporary files

## Future Enhancements

### Planned Features
1. Resume capability for interrupted installations
2. Uninstall functionality
3. Cluster expansion operations
4. Advanced configuration options
5. Integration with monitoring systems

### Architecture Evolution
- Plugin system for custom operations
- Configuration templates for common scenarios
- Integration with configuration management tools
- REST API for programmatic access

## Development Guidelines

### Code Standards
- Functions should be 10-30 lines
- Clear, descriptive function names
- Consistent error handling patterns
- Comprehensive logging

### Testing Requirements
- Unit tests for all public functions
- Integration tests for workflows
- Performance tests for critical paths
- Error condition testing

### Documentation
- Inline comments for complex logic
- Function documentation headers
- Architecture decision records
- User-facing documentation updates