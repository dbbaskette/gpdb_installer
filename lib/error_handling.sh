#!/bin/bash

# Error handling and recovery library for Greenplum Installer
# Provides robust error handling, recovery, and cleanup mechanisms

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# Global error handling settings
set -eE  # Exit on error and inherit error handling to functions
trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR

# Error tracking variables
declare -g ERROR_LOG="/tmp/gpdb_installer_errors.log"
declare -g CLEANUP_FUNCTIONS=()
declare -g ROLLBACK_FUNCTIONS=()

# Function to handle errors
handle_error() {
    local exit_code=$1
    local line_number=$2
    local bash_lineno=$3
    local last_command=$4
    local function_stack=$5
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log error details
    {
        echo "ERROR OCCURRED:"
        echo "  Timestamp: $timestamp"
        echo "  Exit Code: $exit_code"
        echo "  Line Number: $line_number"
        echo "  Last Command: $last_command"
        echo "  Function Stack: $function_stack"
        echo "  Script: ${BASH_SOURCE[1]}"
        echo "---"
    } >> "$ERROR_LOG"
    
    # Display error message
    log_error_with_timestamp "An error occurred in the installer (exit code: $exit_code)"
    log_error "Last command: $last_command"
    log_error "Function stack: $function_stack"
    log_error "See $ERROR_LOG for details"
    
    # Execute cleanup functions
    cleanup_on_error
    
    # Exit with error code
    exit $exit_code
}

# Function to add cleanup function to be executed on error
add_cleanup_function() {
    local cleanup_func="$1"
    CLEANUP_FUNCTIONS+=("$cleanup_func")
}

# Function to add rollback function for recovery
add_rollback_function() {
    local rollback_func="$1"
    ROLLBACK_FUNCTIONS+=("$rollback_func")
}

# Function to execute cleanup functions
cleanup_on_error() {
    log_info "Executing cleanup functions..."
    
    for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
        if declare -f "$cleanup_func" > /dev/null; then
            log_info "Running cleanup function: $cleanup_func"
            "$cleanup_func" || log_warn "Cleanup function $cleanup_func failed"
        fi
    done
}

# Function to execute rollback functions
execute_rollback() {
    log_info "Executing rollback functions..."
    
    for rollback_func in "${ROLLBACK_FUNCTIONS[@]}"; do
        if declare -f "$rollback_func" > /dev/null; then
            log_info "Running rollback function: $rollback_func"
            "$rollback_func" || log_warn "Rollback function $rollback_func failed"
        fi
    done
}

# Function to validate command execution
execute_with_retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    local command="${@:3}"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Executing command (attempt $attempt/$max_attempts): $command"
        
        if eval "$command"; then
            log_success "Command executed successfully"
            return 0
        else
            local exit_code=$?
            log_warn "Command failed with exit code $exit_code"
            
            if [ $attempt -lt $max_attempts ]; then
                log_info "Retrying in $delay seconds..."
                sleep $delay
            fi
            
            attempt=$((attempt + 1))
        fi
    done
    
    log_error "Command failed after $max_attempts attempts: $command"
    return 1
}

# Function to execute command with timeout
execute_with_timeout() {
    local timeout_seconds="$1"
    local command="${@:2}"
    
    log_info "Executing command with timeout ($timeout_seconds seconds): $command"
    
    if timeout "$timeout_seconds" bash -c "$command"; then
        log_success "Command completed within timeout"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Command timed out after $timeout_seconds seconds"
        else
            log_error "Command failed with exit code $exit_code"
        fi
        return $exit_code
    fi
}

# Function to validate prerequisites before execution
validate_prerequisites() {
    local prereq_functions=("$@")
    
    log_info "Validating prerequisites..."
    
    for prereq_func in "${prereq_functions[@]}"; do
        if declare -f "$prereq_func" > /dev/null; then
            log_info "Validating prerequisite: $prereq_func"
            if ! "$prereq_func"; then
                log_error "Prerequisite validation failed: $prereq_func"
                return 1
            fi
        else
            log_error "Prerequisite function not found: $prereq_func"
            return 1
        fi
    done
    
    log_success "All prerequisites validated"
    return 0
}

# Function to create backup before destructive operations
create_backup() {
    local source_path="$1"
    local backup_suffix="${2:-$(date +%Y%m%d_%H%M%S)}"
    
    if [ -e "$source_path" ]; then
        local backup_path="${source_path}.backup_${backup_suffix}"
        log_info "Creating backup: $source_path -> $backup_path"
        
        if cp -r "$source_path" "$backup_path"; then
            log_success "Backup created successfully"
            echo "$backup_path"
        else
            log_error "Failed to create backup"
            return 1
        fi
    else
        log_warn "Source path does not exist, skipping backup: $source_path"
    fi
}

# Function to restore from backup
restore_from_backup() {
    local backup_path="$1"
    local restore_path="$2"
    
    if [ -e "$backup_path" ]; then
        log_info "Restoring from backup: $backup_path -> $restore_path"
        
        # Remove current version if it exists
        if [ -e "$restore_path" ]; then
            rm -rf "$restore_path"
        fi
        
        if cp -r "$backup_path" "$restore_path"; then
            log_success "Backup restored successfully"
            return 0
        else
            log_error "Failed to restore from backup"
            return 1
        fi
    else
        log_error "Backup not found: $backup_path"
        return 1
    fi
}

# Function to handle user interruption (Ctrl+C)
handle_user_interrupt() {
    echo ""
    log_warn "Installation interrupted by user"
    
    read -p "Do you want to perform cleanup? (y/n) [y]: " perform_cleanup
    perform_cleanup=${perform_cleanup:-y}
    
    if [[ "$perform_cleanup" =~ ^[Yy]$ ]]; then
        cleanup_on_error
    fi
    
    log_info "Installation cancelled by user"
    exit 130
}

# Function to setup signal handlers
setup_signal_handlers() {
    # Handle user interruption
    trap handle_user_interrupt SIGINT SIGTERM
    
    # Handle cleanup on exit
    trap cleanup_on_error EXIT
}

# Function to disable error handling temporarily
disable_error_handling() {
    set +e
    trap - ERR
}

# Function to re-enable error handling
enable_error_handling() {
    set -e
    trap 'handle_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" "${FUNCNAME[*]}"' ERR
}

# Function to execute command with error handling disabled
execute_without_error_handling() {
    local command="$1"
    
    disable_error_handling
    eval "$command"
    local exit_code=$?
    enable_error_handling
    
    return $exit_code
}

# Function to check if we're running in dry run mode
is_dry_run() {
    [[ "${DRY_RUN:-false}" == "true" ]]
}

# Function to execute command respecting dry run mode
execute_command() {
    local command="$*"
    
    if is_dry_run; then
        log_info "[DRY-RUN] Would execute: $command"
        return 0
    else
        eval "$command"
    fi
}

# Function to log and execute command
log_and_execute() {
    local description="$1"
    local command="${@:2}"
    
    log_info "$description"
    execute_command "$command"
}

# Standard cleanup functions
cleanup_ssh_sockets() {
    log_info "Cleaning up SSH control sockets..."
    rm -f /tmp/ssh_mux_* 2>/dev/null || true
}

cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/gpinitsystem_config /tmp/machine_list 2>/dev/null || true
}

cleanup_partial_installation() {
    log_info "Cleaning up partial installation..."
    
    # This would be implemented based on what needs to be cleaned up
    # in case of partial installation failure
    log_warn "Partial installation cleanup not yet implemented"
}

# Register standard cleanup functions
add_cleanup_function "cleanup_ssh_sockets"
add_cleanup_function "cleanup_temp_files"