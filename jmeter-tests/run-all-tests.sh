#!/bin/bash

# Master test orchestration script for REST API load testing
# Runs all test scenarios from the test matrix with proper warm-up, test duration, and cool-down periods

set -e

# Configuration
HOST="${HOST:-172.30.189.189}"
PORT="${PORT:-8080}"
PROTOCOL="${PROTOCOL:-http}"
JMETER_HOME="${JMETER_HOME:-/opt/apache-jmeter}"
JMETER_BIN="${JMETER_HOME}/bin/jmeter"

# JMeter JVM configuration - set heap size to 5GB
export JVM_ARGS="-Xms5g -Xmx5g"

# Test timing configuration (in seconds)
WARMUP_TIME=300      # 5 minutes
TEST_DURATION=900    # 15 minutes
COOLDOWN_TIME=300    # 5 minutes
BREAK_TIME=300       # 5 minutes between tests

# Results directory
RESULTS_DIR="results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Log file
LOG_FILE="$RESULTS_DIR/test-execution.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $0.03" | tee -a "$LOG_FILE"
}

# Function to check if JMeter is available
check_jmeter() {
    if [ ! -f "$JMETER_BIN" ]; then
        log "ERROR: JMeter not found at $JMETER_BIN"
        log "Please set JMETER_HOME environment variable or install JMeter"
        exit 1
    fi
    log "JMeter found at: $JMETER_BIN"
}

# Function to run a single test
run_test() {
    local payload_size=$1
    local iteration=$2
    local threads=$3
    local sleep_time=$4
    
    local test_name="test-${payload_size}b-iter${iteration}-${threads}t"
    local test_results_dir="$RESULTS_DIR/$test_name"
    mkdir -p "$test_results_dir"
    
    log "=========================================="
    log "Starting Test: $test_name"
    log "  Payload Size: ${payload_size} bytes"
    log "  Iteration: $iteration"
    log "  Threads: $threads"
    log "  Sleep Time: ${sleep_time}s"
    log "  Warm-up: ${WARMUP_TIME}s ($(($WARMUP_TIME / 60)) min)"
    log "  Duration: ${TEST_DURATION}s ($(($TEST_DURATION / 60)) min)"
    log "  Cool-down: ${COOLDOWN_TIME}s ($(($COOLDOWN_TIME / 60)) min)"
    log "=========================================="
    
    # Calculate total test time including ramp-up
    local total_time=$(($WARMUP_TIME + $TEST_DURATION))
    
    # Run JMeter test
    log "Executing JMeter test..."
    "$JMETER_BIN" -n -t load-test-template.jmx \
        -Jhost="$HOST" \
        -Jport="$PORT" \
        -Jprotocol="$PROTOCOL" \
        -Jthreads="$threads" \
        -Jrampup="$WARMUP_TIME" \
        -Jduration="$total_time" \
        -Jsleep_time="$sleep_time" \
        -Jpayload_size="$payload_size" \
        -l "$test_results_dir/results.csv" \
        -j "$test_results_dir/jmeter.log" \
        -e -o "$test_results_dir/html-report" \
        2>&1 | tee -a "$LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log "✓ Test completed successfully: $test_name"
    else
        log "✗ Test failed with exit code $exit_code: $test_name"
    fi
    
    # Cool-down period
    log "Cool-down period: ${COOLDOWN_TIME}s ($(($COOLDOWN_TIME / 60)) min)"
    sleep $COOLDOWN_TIME
    
    return $exit_code
}

# Function to run break between tests
run_break() {
    log "=========================================="
    log "Break period: ${BREAK_TIME}s ($(($BREAK_TIME / 60)) min)"
    log "=========================================="
    sleep $BREAK_TIME
}

# Main execution
main() {
    log "=========================================="
    log "REST API Load Test Suite"
    log "=========================================="
    log "Configuration:"
    log "  Target: ${PROTOCOL}://${HOST}:${PORT}"
    log "  Results Directory: $RESULTS_DIR"
    log "  Warm-up Time: ${WARMUP_TIME}s ($(($WARMUP_TIME / 60)) min)"
    log "  Test Duration: ${TEST_DURATION}s ($(($TEST_DURATION / 60)) min)"
    log "  Cool-down Time: ${COOLDOWN_TIME}s ($(($COOLDOWN_TIME / 60)) min)"
    log "  Break Time: ${BREAK_TIME}s ($(($BREAK_TIME / 60)) min)"
    log "=========================================="
    
    check_jmeter
    
    # Test matrix based on the provided table
    # Format: payload_size iteration threads sleep_time
    local tests=(
        "1024 1 1 0.03"
        "1024 2 10 0.03"
        "1024 3 100 0.03"
        "1024 4 1000 0.03"
        "4096 1 1 0.03"
        "4096 2 10 0.03"
        "4096 3 100 0.03"
        "4096 4 1000 0.03"
        "51200 1 1 0.03"
        "51200 2 10 0.03"
        "51200 3 100 0.03"
        "51200 4 1000 0.03"
        "204800 1 1 0.03"
        "819200 2 10 0.03"
        "1327200 3 100 0.03"
        "13107200 4 1000 0.03"
        "52428800 1 1 0.03"
        "209715200 2 10 0.03"
        "838860800 3 100 0.03"
        "3355443200 4 1000 0.03"
        "1048576 1 1 0.03"
        "1048576 2 10 0.03"
        "1048576 3 100 0.03"
        "1048576 4 1000 0.03"
        "2097152 1 1 0.03"
        "2097152 2 10 0.03"
        "2097152 3 100 0.03"
        "2097152 4 1000 0.03"
        "5242880 1 1 0.03"
        "5242880 2 10 0.03"
        "5242880 3 100 0.03"
        "5242880 4 1000 0.03"
    )
    
    local total_tests=${#tests[@]}
    local current_test=0
    local failed_tests=0
    
    log "Total tests to run: $total_tests"
    log ""
    
    for test_config in "${tests[@]}"; do
        current_test=$((current_test + 1))
        
        # Parse test configuration
        read -r payload_size iteration threads sleep_time <<< "$test_config"
        
        log "Progress: Test $current_test of $total_tests"
        
        # Run the test
        if ! run_test "$payload_size" "$iteration" "$threads" "$sleep_time"; then
            failed_tests=$((failed_tests + 1))
        fi
        
        # Break between tests (except after the last test)
        if [ $current_test -lt $total_tests ]; then
            run_break
        fi
    done
    
    # Final summary
    log ""
    log "=========================================="
    log "Test Suite Completed"
    log "=========================================="
    log "Total Tests: $total_tests"
    log "Successful: $((total_tests - failed_tests))"
    log "Failed: $failed_tests"
    log "Results Directory: $RESULTS_DIR"
    log "=========================================="
    
    # Generate summary report
    generate_summary_report
    
    if [ $failed_tests -gt 0 ]; then
        exit 1
    fi
}

# Function to generate summary report
generate_summary_report() {
    local summary_file="$RESULTS_DIR/summary-report.txt"
    
    log "Generating summary report: $summary_file"
    
    cat > "$summary_file" << EOF
REST API Load Test Suite - Summary Report
==========================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Configuration:
  Target: ${PROTOCOL}://${HOST}:${PORT}
  Warm-up Time: ${WARMUP_TIME}s ($(($WARMUP_TIME / 60)) min)
  Test Duration: ${TEST_DURATION}s ($(($TEST_DURATION / 60)) min)
  Cool-down Time: ${COOLDOWN_TIME}s ($(($COOLDOWN_TIME / 60)) min)
  Break Time: ${BREAK_TIME}s ($(($BREAK_TIME / 60)) min)

Test Results:
-------------
EOF
    
    # List all test directories and their status
    for test_dir in "$RESULTS_DIR"/test-*; do
        if [ -d "$test_dir" ]; then
            local test_name=$(basename "$test_dir")
            local status="✓ PASSED"
            
            # Check if test failed (look for errors in JMeter log)
            if grep -q "ERROR" "$test_dir/jmeter.log" 2>/dev/null; then
                status="✗ FAILED"
            fi
            
            echo "  $test_name: $status" >> "$summary_file"
        fi
    done
    
    cat >> "$summary_file" << EOF

HTML Reports:
-------------
Each test has an HTML report in its respective directory:
  $RESULTS_DIR/test-*/html-report/index.html

Raw Results:
------------
CSV files for further analysis:
  $RESULTS_DIR/test-*/results.csv

Logs:
-----
Master log: $LOG_FILE
Individual test logs: $RESULTS_DIR/test-*/jmeter.log

==========================================
EOF
    
    log "Summary report generated: $summary_file"
}

# Run main function
main "$@"

# Made with Bob
