#!/bin/bash

# Stepping thread test script - doubles threads every 2 minutes
# Runs 13 cycles from 1 to 4096 threads for each payload size

set -e

# Configuration
HOST="${HOST:-172.30.189.189}"
PORT="${PORT:-8080}"
PROTOCOL="${PROTOCOL:-http}"
JMETER_HOME="${JMETER_HOME:-/opt/apache-jmeter}"
JMETER_BIN="${JMETER_HOME}/bin/jmeter"

# JMeter JVM configuration - optimized for high thread count
# Reduce thread stack size to allow more threads, increase heap
export JVM_ARGS="-Xms6g -Xmx6g -XX:ThreadStackSize=256k -XX:MaxMetaspaceSize=512m -XX:+UseG1GC -XX:MaxGCPauseMillis=100"

# Test timing configuration
STEP_DURATION=120    # 2 minutes per step
TOTAL_STEPS=13       # 13 cycles: 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096
TOTAL_DURATION=$((STEP_DURATION * TOTAL_STEPS))  # 26 minutes total
BREAK_TIME=30        # 30 seconds between tests

# Results directory
RESULTS_DIR="results/stepping-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Log file
LOG_FILE="$RESULTS_DIR/test-execution.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
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

# Function to run a single stepping test
run_stepping_test() {
    local payload_size=$1
    local sleep_time=$2
    
    local test_name="stepping-test-${payload_size}b"
    local test_results_dir="$RESULTS_DIR/$test_name"
    mkdir -p "$test_results_dir"
    
    log "=========================================="
    log "Starting Stepping Test: $test_name"
    log "  Payload Size: ${payload_size} bytes"
    log "  Sleep Time: ${sleep_time}s"
    log "  Step Duration: ${STEP_DURATION}s (2 min)"
    log "  Total Steps: $TOTAL_STEPS"
    log "  Thread Progression: 1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 → 256 → 512 → 1024 → 2048 → 4096"
    log "  Total Duration: ${TOTAL_DURATION}s ($((TOTAL_DURATION / 60)) min)"
    log "=========================================="
    
    # Run JMeter test with stepping thread group
    log "Executing JMeter stepping test..."
    "$JMETER_BIN" -n -t stepping-load-test.jmx \
        -Jhost="$HOST" \
        -Jport="$PORT" \
        -Jprotocol="$PROTOCOL" \
        -Jstep_duration="$STEP_DURATION" \
        -Jtotal_steps="$TOTAL_STEPS" \
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
    
    return $exit_code
}

# Function to run break between tests
run_break() {
    log "=========================================="
    log "Break period: ${BREAK_TIME}s"
    log "=========================================="
    sleep $BREAK_TIME
}

# Main execution
main() {
    log "=========================================="
    log "REST API Stepping Load Test Suite"
    log "=========================================="
    log "Configuration:"
    log "  Target: ${PROTOCOL}://${HOST}:${PORT}"
    log "  Results Directory: $RESULTS_DIR"
    log "  Step Duration: ${STEP_DURATION}s (2 min)"
    log "  Total Steps: $TOTAL_STEPS"
    log "  Total Test Duration: ${TOTAL_DURATION}s ($((TOTAL_DURATION / 60)) min)"
    log "  Break Time: ${BREAK_TIME}s"
    log "=========================================="
    
    check_jmeter
    
    # Payload sizes to test (in bytes)
    # 1KB, 4KB, 50KB, 200KB, 1MB, 2MB, 5MB
    local payload_sizes=(
        "1024"
        "4096"
        "51200"
        "204800"
        "1048576"
        "2097152"
        "5242880"
    )
    
    local sleep_time="0.03"
    local total_tests=${#payload_sizes[@]}
    local current_test=0
    local failed_tests=0
    
    log "Total payload sizes to test: $total_tests"
    log "Payload sizes: ${payload_sizes[*]}"
    log ""
    
    for payload_size in "${payload_sizes[@]}"; do
        current_test=$((current_test + 1))
        
        log "Progress: Test $current_test of $total_tests"
        
        # Run the stepping test
        if ! run_stepping_test "$payload_size" "$sleep_time"; then
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
REST API Stepping Load Test Suite - Summary Report
===================================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')

Configuration:
  Target: ${PROTOCOL}://${HOST}:${PORT}
  Step Duration: ${STEP_DURATION}s (2 min)
  Total Steps: $TOTAL_STEPS
  Thread Progression: 1 → 2 → 4 → 8 → 16 → 32 → 64 → 128 → 256 → 512 → 1024 → 2048 → 4096
  Total Test Duration: ${TOTAL_DURATION}s ($((TOTAL_DURATION / 60)) min)
  Break Time: ${BREAK_TIME}s

Test Results:
-------------
EOF
    
    # List all test directories and their status
    for test_dir in "$RESULTS_DIR"/stepping-test-*; do
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
  $RESULTS_DIR/stepping-test-*/html-report/index.html

Raw Results:
------------
CSV files for further analysis:
  $RESULTS_DIR/stepping-test-*/results.csv

Logs:
-----
Master log: $LOG_FILE
Individual test logs: $RESULTS_DIR/stepping-test-*/jmeter.log

===================================================
EOF
    
    log "Summary report generated: $summary_file"
}

# Run main function
main "$@"

# Made with Bob
