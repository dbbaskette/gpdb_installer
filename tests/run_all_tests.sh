#!/bin/bash

# Main test runner for Greenplum Installer test suite

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source test framework
source "$SCRIPT_DIR/test_framework.sh"

# Test runner configuration
VERBOSE=false
TEST_PATTERN="test_*.sh"
PARALLEL_TESTS=false
COVERAGE_MODE=false

# Function to show help
show_test_help() {
    cat << EOF
Usage: $0 [OPTIONS] [TEST_PATTERN]

Run the Greenplum Installer test suite.

OPTIONS:
    -v, --verbose       Enable verbose output
    -p, --parallel      Run tests in parallel (experimental)
    -c, --coverage      Enable coverage reporting
    -h, --help          Show this help message
    --list              List available tests
    --quick             Run only quick tests (skip integration tests)
    --integration       Run only integration tests
    --unit              Run only unit tests

TEST_PATTERN:
    Optional pattern to match test files (default: test_*.sh)
    Examples: test_config.sh, test_ssh.sh, test_validation.sh

EXAMPLES:
    $0                      # Run all tests
    $0 -v                   # Run all tests with verbose output
    $0 test_config.sh       # Run only configuration tests
    $0 --unit               # Run only unit tests
    $0 --integration        # Run only integration tests

EOF
}

# Function to list available tests
list_tests() {
    echo "Available tests:"
    echo "================"
    
    for test_file in "$SCRIPT_DIR"/test_*.sh; do
        if [ -f "$test_file" ] && [ "$(basename "$test_file")" != "test_framework.sh" ]; then
            local test_name=$(basename "$test_file" .sh)
            local test_description=$(grep -m1 "^# .*tests for" "$test_file" | sed 's/^# //' || echo "No description")
            printf "%-20s - %s\n" "$test_name" "$test_description"
        fi
    done
    
    echo ""
}

# Function to parse command line arguments
parse_test_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -p|--parallel)
                PARALLEL_TESTS=true
                shift
                ;;
            -c|--coverage)
                COVERAGE_MODE=true
                shift
                ;;
            -h|--help)
                show_test_help
                exit 0
                ;;
            --list)
                list_tests
                exit 0
                ;;
            --quick)
                TEST_PATTERN="test_validation.sh test_config.sh test_ssh.sh"
                shift
                ;;
            --unit)
                TEST_PATTERN="test_validation.sh test_config.sh test_ssh.sh test_system.sh test_greenplum.sh"
                shift
                ;;
            --integration)
                TEST_PATTERN="test_integration.sh"
                shift
                ;;
            test_*.sh)
                TEST_PATTERN="$1"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_test_help
                exit 1
                ;;
        esac
    done
}

# Function to run tests in parallel
run_tests_parallel() {
    local test_files=("$@")
    local pids=()
    
    test_log "Running tests in parallel mode"
    
    # Start all tests in background
    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            local test_name=$(basename "$test_file" .sh)
            local log_file="$TEST_TEMP_DIR/test_${test_name}.log"
            
            test_info "Starting test: $test_name"
            bash "$test_file" > "$log_file" 2>&1 &
            pids+=($!)
        fi
    done
    
    # Wait for all tests to complete
    local failed_tests=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed_tests=$((failed_tests + 1))
        fi
    done
    
    # Show results
    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            local test_name=$(basename "$test_file" .sh)
            local log_file="$TEST_TEMP_DIR/test_${test_name}.log"
            
            if [ -f "$log_file" ]; then
                if [ "$VERBOSE" = true ]; then
                    cat "$log_file"
                else
                    # Show summary only
                    grep -E "\[(PASS|FAIL|SKIP)\]" "$log_file" | tail -5
                fi
            fi
        fi
    done
    
    return $failed_tests
}

# Function to run tests sequentially
run_tests_sequential() {
    local test_files=("$@")
    local failed_tests=0
    
    test_log "Running tests in sequential mode"
    
    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ]; then
            local test_name=$(basename "$test_file" .sh)
            
            test_info "Running test file: $test_name"
            
            if [ "$VERBOSE" = true ]; then
                bash "$test_file"
            else
                # Capture output and show summary
                local output=$(bash "$test_file" 2>&1)
                local exit_code=$?
                
                if [ $exit_code -eq 0 ]; then
                    test_success "Test file passed: $test_name"
                else
                    test_failure "Test file failed: $test_name"
                    failed_tests=$((failed_tests + 1))
                    
                    # Show failure details
                    echo "$output" | grep -E "\[(FAIL|ERROR)\]" | head -10
                fi
            fi
            
            echo ""
        fi
    done
    
    return $failed_tests
}

# Function to setup test environment
setup_test_runner() {
    test_log "Setting up test runner environment"
    
    # Create temporary directory for test outputs
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
    
    # Setup coverage if requested
    if [ "$COVERAGE_MODE" = true ]; then
        test_info "Coverage mode enabled"
        # Coverage setup would go here
    fi
    
    # Verify libraries exist
    if [ ! -d "$ROOT_DIR/lib" ]; then
        test_failure "Library directory not found: $ROOT_DIR/lib"
        exit 1
    fi
    
    # Source test framework
    source "$SCRIPT_DIR/test_framework.sh"
    
    test_info "Test runner setup completed"
}

# Function to cleanup test environment
cleanup_test_runner() {
    test_info "Cleaning up test runner environment"
    
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        rm -rf "$TEST_TEMP_DIR"
        test_info "Test runner cleanup completed"
    fi
}

# Function to collect test files
collect_test_files() {
    local pattern="$1"
    local test_files=()
    
    if [[ "$pattern" =~ ^test_.*\.sh$ ]]; then
        # Single test file specified
        local test_file="$SCRIPT_DIR/$pattern"
        if [ -f "$test_file" ]; then
            test_files+=("$test_file")
        else
            test_failure "Test file not found: $pattern"
            exit 1
        fi
    else
        # Pattern or multiple files
        for test_file in $SCRIPT_DIR/$pattern; do
            if [ -f "$test_file" ] && [ "$(basename "$test_file")" != "test_framework.sh" ] && [ "$(basename "$test_file")" != "run_all_tests.sh" ]; then
                test_files+=("$test_file")
            fi
        done
    fi
    
    if [ ${#test_files[@]} -eq 0 ]; then
        test_failure "No test files found matching pattern: $pattern"
        exit 1
    fi
    
    echo "${test_files[@]}"
}

# Function to run performance tests
run_performance_tests() {
    test_log "Running performance tests"
    
    # Test library loading performance
    start_timer
    test_library_loading
    stop_timer
    
    assert_performance "1.0" "Library loading performance"
    
    # Test configuration loading performance
    local test_config="$TEST_TEMP_DIR/perf_test_config.conf"
    cat > "$test_config" << EOF
GPDB_COORDINATOR_HOST="perf-coordinator"
GPDB_SEGMENT_HOSTS=(perf-segment1 perf-segment2)
GPDB_INSTALL_DIR="/usr/local/greenplum-perf"
GPDB_DATA_DIR="/data/primary-perf"
EOF
    
    start_timer
    source "$ROOT_DIR/lib/config.sh" >/dev/null 2>&1
    load_configuration "$test_config" >/dev/null 2>&1
    stop_timer
    
    assert_performance "0.5" "Configuration loading performance"
}

# Function to generate test report
generate_test_report() {
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    local success_rate=0
    
    if [ $total_tests -gt 0 ]; then
        success_rate=$((TESTS_PASSED * 100 / total_tests))
    fi
    
    cat << EOF

================================
Test Execution Report
================================
Total Tests: $total_tests
Passed: $TESTS_PASSED
Failed: $TESTS_FAILED
Skipped: $TESTS_SKIPPED
Success Rate: ${success_rate}%

Test Environment:
- Test Directory: $SCRIPT_DIR
- Root Directory: $ROOT_DIR
- Verbose Mode: $VERBOSE
- Parallel Mode: $PARALLEL_TESTS
- Coverage Mode: $COVERAGE_MODE

EOF
    
    if [ $TESTS_FAILED -gt 0 ]; then
        echo "⚠️  Some tests failed. Please review the output above."
        return 1
    else
        echo "✅ All tests passed successfully!"
        return 0
    fi
}

# Main test execution function
main() {
    # Parse arguments
    parse_test_arguments "$@"
    
    # Setup test environment
    setup_test_runner
    
    # Setup signal handlers
    trap cleanup_test_runner EXIT
    
    # Show test information
    test_log "Starting Greenplum Installer Test Suite"
    test_info "Test Pattern: $TEST_PATTERN"
    test_info "Verbose Mode: $VERBOSE"
    test_info "Parallel Mode: $PARALLEL_TESTS"
    
    # Collect test files
    local test_files=($(collect_test_files "$TEST_PATTERN"))
    test_info "Found ${#test_files[@]} test files"
    
    # Run tests
    local failed_tests=0
    if [ "$PARALLEL_TESTS" = true ]; then
        run_tests_parallel "${test_files[@]}"
        failed_tests=$?
    else
        run_tests_sequential "${test_files[@]}"
        failed_tests=$?
    fi
    
    # Run performance tests if requested
    if [ "$COVERAGE_MODE" = true ]; then
        run_performance_tests
    fi
    
    # Generate test report
    if ! generate_test_report; then
        exit 1
    fi
    
    # Exit with appropriate code
    if [ $failed_tests -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Execute main function
main "$@"