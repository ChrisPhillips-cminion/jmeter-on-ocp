#!/bin/bash

# Stepping thread test script - doubles threads every 2 minutes
# Usage: ./run-stepping-test.sh [payload_size] [max_threads]
# Example: ./run-stepping-test.sh 1024 1024
# Example: ./run-stepping-test.sh 4096 2048

set -e

# Parse command line arguments
PAYLOAD_SIZE_ARG="${1:-}"
MAX_THREADS_ARG="${2:-}"

# Configuration
HOST="${HOST:-172.30.251.96}"
PORT="${PORT:-443}"
PROTOCOL="${PROTOCOL:-https}"
HOST_HEADER="${HOST_HEADER:-}"
JMETER_HOME="${JMETER_HOME:-/opt/apache-jmeter}"
JMETER_BIN="${JMETER_HOME}/bin/jmeter"

# JMeter JVM configuration - optimized for high thread count
# Reduce thread stack size to allow more threads, increase heap
# Use HEAP for memory settings and JVM_ARGS for other settings
export HEAP="-Xms6g -Xmx6g"
export JVM_ARGS="-Xss256k -XX:MaxMetaspaceSize=512m -XX:+UseG1GC -XX:MaxGCPauseMillis=100 -Djava.net.preferIPv4Stack=true"

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

# Function to calculate max threads based on payload size
# Note: These are per-pod values. With 4 replicas, total threads = max_threads * 4
calculate_max_threads() {
    local payload_size=$1
    local max_threads=$2
    
    # If max_threads is provided, use it
    if [ -n "$max_threads" ]; then
        echo "$max_threads"
        return
    fi
    
    # Otherwise, calculate based on payload size
    # Rule: Inverse relationship - smaller payload = more threads per pod
    # Divided by 4 since we'll run 4 replicas (total = per_pod * 4)
    if [ "$payload_size" -le 1024 ]; then
        # 1KB payload -> 1024 threads per pod (4096 total across 4 pods)
        echo "1024"
    elif [ "$payload_size" -le 4096 ]; then
        # 4KB payload -> 512 threads per pod (2048 total across 4 pods)
        echo "512"
    elif [ "$payload_size" -le 51200 ]; then
        # 50KB payload -> 256 threads per pod (1024 total across 4 pods)
        echo "256"
    elif [ "$payload_size" -le 204800 ]; then
        # 200KB payload -> 128 threads per pod (512 total across 4 pods)
        echo "128"
    elif [ "$payload_size" -le 1048576 ]; then
        # 1MB payload -> 64 threads per pod (256 total across 4 pods)
        echo "64"
    elif [ "$payload_size" -le 2097152 ]; then
        # 2MB payload -> 32 threads per pod (128 total across 4 pods)
        echo "32"
    else
        # 5MB+ payload -> 16 threads per pod (64 total across 4 pods)
        echo "16"
    fi
}

# Function to calculate number of steps based on max threads
calculate_steps() {
    local max_threads=$1
    local steps=1
    local current=$max_threads
    
    # Count steps by halving until we reach 1
    while [ $current -gt 1 ]; do
        current=$((current / 2))
        steps=$((steps + 1))
    done
    
    echo "$steps"
}

# Function to generate thread progression string (descending)
generate_thread_progression() {
    local max_threads=$1
    local progression="$max_threads"
    local current=$max_threads
    
    # Generate descending progression by halving
    while [ $current -gt 1 ]; do
        current=$((current / 2))
        progression="$progression → $current"
    done
    
    echo "$progression"
}

# Function to generate Ultimate Thread Group configuration
generate_thread_group_config() {
    local max_threads=$1
    local step_duration=$2
    local config=""
    local current=$max_threads
    local step_num=1
    local start_time=0
    local ramp_time=30
    local shutdown_time=10
    
    # Generate steps from max_threads down to 1 (halving each time)
    while [ $current -ge 1 ]; do
        config="${config}          <collectionProp name=\"step${step_num}\">
            <stringProp name=\"threads\">${current}</stringProp>
            <stringProp name=\"initial_delay\">${start_time}</stringProp>
            <stringProp name=\"startup_time\">${ramp_time}</stringProp>
            <stringProp name=\"hold_load\">${step_duration}</stringProp>
            <stringProp name=\"shutdown_time\">${shutdown_time}</stringProp>
          </collectionProp>
"
        start_time=$((start_time + step_duration + ramp_time + shutdown_time))
        step_num=$((step_num + 1))
        
        # Stop at 1 thread
        if [ $current -eq 1 ]; then
            break
        fi
        
        current=$((current / 2))
    done
    
    echo "$config"
}

# Function to run a single stepping test
run_stepping_test() {
    local payload_size=$1
    local sleep_time=$2
    local max_threads=$3
    
    local test_name="stepping-test-${payload_size}b-${max_threads}t"
    local test_results_dir="$RESULTS_DIR/$test_name"
    mkdir -p "$test_results_dir"
    
    local steps=$(calculate_steps "$max_threads")
    local duration=$((STEP_DURATION * steps))
    local thread_progression=$(generate_thread_progression "$max_threads")
    
    log "=========================================="
    log "Starting Stepping Test: $test_name"
    log "  Payload Size: ${payload_size} bytes"
    log "  Max Threads per Pod: ${max_threads}"
    log "  Total Threads (4 replicas): $((max_threads * 4))"
    log "  Sleep Time: ${sleep_time}s"
    log "  Step Duration: ${STEP_DURATION}s (2 min)"
    log "  Total Steps: $steps"
    log "  Thread Progression per Pod (descending): $thread_progression"
    log "  Total Duration: ${duration}s ($((duration / 60)) min)"
    log "=========================================="
    
    # Generate dynamic JMX file with descending thread configuration
    local dynamic_jmx="$test_results_dir/dynamic-test.jmx"
    log "Generating dynamic JMX configuration..."
    
    local thread_group_config=$(generate_thread_group_config "$max_threads" "$STEP_DURATION")
    
    cat > "$dynamic_jmx" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.6.3">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="REST API Descending Load Test" enabled="true">
      <stringProp name="TestPlan.comments">Descending load test: ${max_threads}→1 (halving each step)</stringProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
        <collectionProp name="Arguments.arguments">
          <elementProp name="HOST" elementType="Argument">
            <stringProp name="Argument.name">HOST</stringProp>
            <stringProp name="Argument.value">${HOST}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PORT" elementType="Argument">
            <stringProp name="Argument.name">PORT</stringProp>
            <stringProp name="Argument.value">${PORT}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PROTOCOL" elementType="Argument">
            <stringProp name="Argument.name">PROTOCOL</stringProp>
            <stringProp name="Argument.value">${PROTOCOL}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="HOST_HEADER" elementType="Argument">
            <stringProp name="Argument.name">HOST_HEADER</stringProp>
            <stringProp name="Argument.value">${HOST_HEADER}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="SLEEP_TIME" elementType="Argument">
            <stringProp name="Argument.name">SLEEP_TIME</stringProp>
            <stringProp name="Argument.value">${sleep_time}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="PAYLOAD_SIZE" elementType="Argument">
            <stringProp name="Argument.name">PAYLOAD_SIZE</stringProp>
            <stringProp name="Argument.value">${payload_size}</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
    </TestPlan>
    <hashTree>
      <kg.apc.jmeter.threads.UltimateThreadGroup guiclass="kg.apc.jmeter.threads.UltimateThreadGroupGui" testclass="kg.apc.jmeter.threads.UltimateThreadGroup" testname="Ultimate Thread Group (${max_threads}→1)" enabled="true">
        <collectionProp name="ultimatethreadgroupdata">
${thread_group_config}        </collectionProp>
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControllerGui" testclass="LoopController" testname="Loop Controller" enabled="true">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <intProp name="LoopController.loops">-1</intProp>
        </elementProp>
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
      </kg.apc.jmeter.threads.UltimateThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="POST /1.0.0/perf/test" enabled="true">
          <boolProp name="HTTPSampler.postBodyRaw">true</boolProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{&#xd;
  "timestamp": "\${__time(yyyy-MM-dd'T'HH:mm:ss.SSS'Z',)}",&#xd;
  "test_id": "\${__UUID()}",&#xd;
  "thread": "\${__threadNum()}",&#xd;
  "iteration": "\${__counter(FALSE,)}",&#xd;
  "payload_size": \${PAYLOAD_SIZE},&#xd;
  "data": "\${__RandomString(\${PAYLOAD_SIZE},abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,)}"&#xd;
}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">\${HOST}</stringProp>
          <stringProp name="HTTPSampler.port">\${PORT}</stringProp>
          <stringProp name="HTTPSampler.protocol">\${PROTOCOL}</stringProp>
          <stringProp name="HTTPSampler.contentEncoding">UTF-8</stringProp>
          <stringProp name="HTTPSampler.path">/1.0.0/perf/test?sleep_time=\${SLEEP_TIME}</stringProp>
          <stringProp name="HTTPSampler.method">POST</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
          <stringProp name="HTTPSampler.embedded_url_re"></stringProp>
          <stringProp name="HTTPSampler.connect_timeout"></stringProp>
          <stringProp name="HTTPSampler.response_timeout"></stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="HTTP Header Manager" enabled="true">
            <collectionProp name="HeaderManager.headers">
              <elementProp name="" elementType="Header">
                <stringProp name="Header.name">Content-Type</stringProp>
                <stringProp name="Header.value">application/json</stringProp>
              </elementProp>
EOF
    
    # Add Host header if HOST_HEADER is set
    if [ -n "$HOST_HEADER" ]; then
        cat >> "$dynamic_jmx" << EOF
              <elementProp name="" elementType="Header">
                <stringProp name="Header.name">Host</stringProp>
                <stringProp name="Header.value">\${HOST_HEADER}</stringProp>
              </elementProp>
EOF
    fi
    
    cat >> "$dynamic_jmx" << EOF
            </collectionProp>
          </HeaderManager>
          <hashTree/>
          <ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion" testname="Response Code Assertion" enabled="true">
            <collectionProp name="Asserion.test_strings">
              <stringProp name="49586">200</stringProp>
            </collectionProp>
            <stringProp name="Assertion.custom_message"></stringProp>
            <stringProp name="Assertion.test_field">Assertion.response_code</stringProp>
            <boolProp name="Assertion.assume_success">false</boolProp>
            <intProp name="Assertion.test_type">8</intProp>
          </ResponseAssertion>
          <hashTree/>
          <JSONPathAssertion guiclass="JSONPathAssertionGui" testclass="JSONPathAssertion" testname="JSON Status Assertion" enabled="true">
            <stringProp name="JSON_PATH">\$.status</stringProp>
            <stringProp name="EXPECTED_VALUE">success</stringProp>
            <boolProp name="JSONVALIDATION">true</boolProp>
            <boolProp name="EXPECT_NULL">false</boolProp>
            <boolProp name="INVERT">false</boolProp>
            <boolProp name="ISREGEX">false</boolProp>
          </JSONPathAssertion>
          <hashTree/>
        </hashTree>
        <ConstantTimer guiclass="ConstantTimerGui" testclass="ConstantTimer" testname="Think Time" enabled="true">
          <stringProp name="ConstantTimer.delay">100</stringProp>
        </ConstantTimer>
        <hashTree/>
      </hashTree>
      <ResultCollector guiclass="SummaryReport" testclass="ResultCollector" testname="Summary Report" enabled="true">
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
          <name>saveConfig</name>
          <value class="SampleSaveConfiguration">
            <time>true</time>
            <latency>true</latency>
            <timestamp>true</timestamp>
            <success>true</success>
            <label>true</label>
            <code>true</code>
            <message>true</message>
            <threadName>true</threadName>
            <dataType>true</dataType>
            <encoding>false</encoding>
            <assertions>true</assertions>
            <subresults>true</subresults>
            <responseData>false</responseData>
            <samplerData>false</samplerData>
            <xml>false</xml>
            <fieldNames>true</fieldNames>
            <responseHeaders>false</responseHeaders>
            <requestHeaders>false</requestHeaders>
            <responseDataOnError>false</responseDataOnError>
            <saveAssertionResultsFailureMessage>true</saveAssertionResultsFailureMessage>
            <assertionsResultsToSave>0</assertionsResultsToSave>
            <bytes>true</bytes>
            <sentBytes>true</sentBytes>
            <url>true</url>
            <threadCounts>true</threadCounts>
            <idleTime>true</idleTime>
            <connectTime>true</connectTime>
          </value>
        </objProp>
        <stringProp name="filename"></stringProp>
      </ResultCollector>
      <hashTree/>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOF
    
    # Run JMeter test with dynamically generated JMX
    log "Executing JMeter descending load test..."
    "$JMETER_BIN" -n -t "$dynamic_jmx" \
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
    
    check_jmeter
    
    # If both payload size and max threads are provided, run single test
    if [ -n "$PAYLOAD_SIZE_ARG" ] && [ -n "$MAX_THREADS_ARG" ]; then
        log "Running single test mode"
        log "Configuration:"
        log "  Target: ${PROTOCOL}://${HOST}:${PORT}"
        log "  Results Directory: $RESULTS_DIR"
        log "  Payload Size: ${PAYLOAD_SIZE_ARG} bytes"
        log "  Max Threads: ${MAX_THREADS_ARG}"
        log "  Step Duration: ${STEP_DURATION}s (2 min)"
        log "  Break Time: ${BREAK_TIME}s"
        log "=========================================="
        
        local sleep_time="0.03"
        
        if ! run_stepping_test "$PAYLOAD_SIZE_ARG" "$sleep_time" "$MAX_THREADS_ARG"; then
            log "Test failed"
            exit 1
        fi
        
        generate_summary_report
        return
    fi
    
    # If only payload size is provided, calculate max threads
    if [ -n "$PAYLOAD_SIZE_ARG" ]; then
        local max_threads=$(calculate_max_threads "$PAYLOAD_SIZE_ARG" "")
        log "Running single test mode with calculated max threads"
        log "Configuration:"
        log "  Target: ${PROTOCOL}://${HOST}:${PORT}"
        log "  Results Directory: $RESULTS_DIR"
        log "  Payload Size: ${PAYLOAD_SIZE_ARG} bytes"
        log "  Max Threads: ${max_threads} (calculated)"
        log "  Step Duration: ${STEP_DURATION}s (2 min)"
        log "  Break Time: ${BREAK_TIME}s"
        log "=========================================="
        
        local sleep_time="0.03"
        
        if ! run_stepping_test "$PAYLOAD_SIZE_ARG" "$sleep_time" "$max_threads"; then
            log "Test failed"
            exit 1
        fi
        
        generate_summary_report
        return
    fi
    
    # Default: run all payload sizes with calculated max threads
    log "Running full test suite mode"
    log "Configuration:"
    log "  Target: ${PROTOCOL}://${HOST}:${PORT}"
    log "  Results Directory: $RESULTS_DIR"
    log "  Step Duration: ${STEP_DURATION}s (2 min)"
    log "  Break Time: ${BREAK_TIME}s"
    log "=========================================="
    
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
        
        # Calculate max threads for this payload size
        local max_threads=$(calculate_max_threads "$payload_size" "")
        log "Max threads for ${payload_size}b: ${max_threads}"
        
        # Run the stepping test
        if ! run_stepping_test "$payload_size" "$sleep_time" "$max_threads"; then
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
  Break Time: ${BREAK_TIME}s
  
Note: Each test has different max threads based on payload size

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
