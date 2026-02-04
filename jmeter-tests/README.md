# JMeter Load Testing Suite

Comprehensive load testing suite for the REST API Sleep Service with automated test execution based on a predefined test matrix. Can be run locally, in Docker, or as an OpenShift Job.

## Overview

This test suite executes a series of load tests with varying:
- **Payload sizes**: From 1KB to 5MB
- **Thread counts**: 1, 10, 100, and 1000 concurrent users
- **Test iterations**: Multiple runs per configuration
- **Timing**: 5-minute warm-up, 15-minute test duration, 5-minute cool-down, 5-minute breaks

## Test Matrix

The test suite runs 32 different test scenarios based on the following matrix:

| Payload Size (bytes) | Iteration | Threads | Sleep Time | Duration |
|---------------------|-----------|---------|------------|----------|
| 1024                | 1         | 1       | 1 second   | 15 min   |
| 1024                | 2         | 10      | 1 second   | 15 min   |
| 1024                | 3         | 100     | 1 second   | 15 min   |
| 1024                | 4         | 1000    | 1 second   | 15 min   |
| 4096                | 1         | 1       | 1 second   | 15 min   |
| 4096                | 2         | 10      | 1 second   | 15 min   |
| 4096                | 3         | 100     | 1 second   | 15 min   |
| 4096                | 4         | 1000    | 1 second   | 15 min   |
| 51200               | 1         | 1       | 1 second   | 15 min   |
| 51200               | 2         | 10      | 1 second   | 15 min   |
| 51200               | 3         | 100     | 1 second   | 15 min   |
| 51200               | 4         | 1000    | 1 second   | 15 min   |
| 204800              | 1         | 1       | 1 second   | 15 min   |
| 819200              | 2         | 10      | 1 second   | 15 min   |
| 1327200             | 3         | 100     | 1 second   | 15 min   |
| 13107200            | 4         | 1000    | 1 second   | 15 min   |
| 52428800            | 1         | 1       | 1 second   | 15 min   |
| 209715200           | 2         | 10      | 1 second   | 15 min   |
| 838860800           | 3         | 100     | 1 second   | 15 min   |
| 3355443200          | 4         | 1000    | 1 second   | 15 min   |
| 1048576             | 1         | 1       | 1 second   | 15 min   |
| 1048576             | 2         | 10      | 1 second   | 15 min   |
| 1048576             | 3         | 100     | 1 second   | 15 min   |
| 1048576             | 4         | 1000    | 1 second   | 15 min   |
| 2097152             | 1         | 1       | 1 second   | 15 min   |
| 2097152             | 2         | 10      | 1 second   | 15 min   |
| 2097152             | 3         | 100     | 1 second   | 15 min   |
| 2097152             | 4         | 1000    | 1 second   | 15 min   |
| 5242880             | 1         | 1       | 1 second   | 15 min   |
| 5242880             | 2         | 10      | 1 second   | 15 min   |
| 5242880             | 3         | 100     | 1 second   | 15 min   |
| 5242880             | 4         | 1000    | 1 second   | 15 min   |

**Total: 32 test scenarios**
- Payload sizes range from 1KB to 5MB
- Thread counts: 1, 10, 100, 1000 concurrent users
- Each test includes 5-minute warm-up, 15-minute execution, 5-minute cool-down
- 5-minute break between tests

## Files

- **`load-test-template.jmx`** - JMeter test plan template with parameterized configuration
- **`run-all-tests.sh`** - Master orchestration script that runs all test scenarios
- **`generate_payload.py`** - Python utility to generate JSON payloads of specific sizes
- **`Dockerfile`** - Container image for running tests
- **`docker-compose.yml`** - Docker Compose configuration
- **`openshift/buildconfig.yaml`** - OpenShift BuildConfig for container image
- **`openshift/jmeter-job.yaml`** - OpenShift Job definition for running tests
- **`README.md`** - This file

## Prerequisites

### JMeter Installation

1. **Download JMeter**:
   ```bash
   wget https://dlcdn.apache.org//jmeter/binaries/apache-jmeter-5.6.3.tgz
   tar -xzf apache-jmeter-5.6.3.tgz
   sudo mv apache-jmeter-5.6.3 /opt/apache-jmeter
   ```

2. **Set environment variable**:
   ```bash
   export JMETER_HOME=/opt/apache-jmeter
   export PATH=$JMETER_HOME/bin:$PATH
   ```

3. **Verify installation**:
   ```bash
   jmeter --version
   ```

### Target Service

Ensure the REST API service is deployed and accessible:
```bash
# Get the service URL from OpenShift
oc get route rest-api-app -o jsonpath='{.spec.host}'

# Test the service
curl http://<service-url>/health
```

## Quick Start

### Run All Tests

Execute the complete test suite with default settings:

```bash
cd jmeter-tests
./run-all-tests.sh
```

### Run with Custom Configuration

Override default settings using environment variables:

```bash
# Set target host and port
export HOST="rest-api-app-your-namespace.apps.cluster.example.com"
export PORT="443"
export PROTOCOL="https"

# Set JMeter location if not in default path
export JMETER_HOME="/path/to/apache-jmeter"

# Run tests
./run-all-tests.sh
```

### Run Single Test

Execute a single test scenario manually:

```bash
jmeter -n -t load-test-template.jmx \
  -Jhost="172.30.189.189" \
  -Jport="8080" \
  -Jprotocol="http" \
  -Jthreads="10" \
  -Jrampup="300" \
  -Jduration="900" \
  -Jsleep_time="1" \
  -Jpayload_size="1024" \
  -l results/test-results.jtl \
  -j results/jmeter.log \
  -e -o results/html-report
```

## Running in Docker

### Build and Run with Docker

```bash
cd jmeter-tests

# Build the image
docker build -t jmeter-tests:latest .

# Run with default settings
docker run --rm \
  -v $(pwd)/results:/jmeter/results \
  jmeter-tests:latest

# Run with custom configuration
docker run --rm \
  -e HOST="your-service-host" \
  -e PORT="8080" \
  -e PROTOCOL="http" \
  -v $(pwd)/results:/jmeter/results \
  jmeter-tests:latest
```

## Running on OpenShift

### Automated Deployment

Use the deployment script for easy setup:

```bash
cd jmeter-tests/openshift
./deploy.sh
```

The script will:
1. Prompt for GitHub repository URL and configuration
2. Create BuildConfig and ImageStream
3. Build the JMeter container image
4. Deploy as a Deployment (not a Job)
5. Start tests automatically
6. Keep pod running after tests complete for result retrieval

### Manual Deployment

1. **Update BuildConfig**:
   Edit `openshift/buildconfig.yaml` and replace:
   - `YOUR_USERNAME/YOUR_REPO_NAME` with your GitHub repository

2. **Create BuildConfig and ImageStream**:
   ```bash
   oc apply -f openshift/buildconfig.yaml
   ```

3. **Start the build**:
   ```bash
   oc start-build jmeter-tests --follow
   ```

4. **Update Deployment**:
   Edit `openshift/deployment.yaml` and replace:
   - `YOUR_NAMESPACE` with your OpenShift project/namespace
   - Adjust `HOST` environment variable to point to your target service

5. **Deploy the application**:
   ```bash
   oc apply -f openshift/deployment.yaml
   ```

### Monitor Test Execution

```bash
# Get pod name
POD_NAME=$(oc get pod -l app=jmeter-tests -o jsonpath='{.items[0].metadata.name}')

# Follow logs in real-time
oc logs -f $POD_NAME

# Check pod status
oc get pod $POD_NAME
```

### Retrieve Results

After tests complete, the pod remains running so you can retrieve results:

```bash
# Get pod name
POD_NAME=$(oc get pod -l app=jmeter-tests -o jsonpath='{.items[0].metadata.name}')

# Copy all results to local directory
oc rsync $POD_NAME:/jmeter/results ./local-results

# List results in pod
oc exec $POD_NAME -- ls -lh /jmeter/results

# View specific result file
oc exec $POD_NAME -- cat /jmeter/results/YYYYMMDD-HHMMSS/summary-report.txt
```

### Cleanup

```bash
# Delete deployment and service
oc delete deployment jmeter-tests
oc delete service jmeter-tests

# Optionally delete build resources
oc delete bc jmeter-tests
oc delete is jmeter-tests
```

## Test Parameters

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HOST` | `172.30.189.189` | Target service hostname or IP |
| `PORT` | `8080` | Target service port |
| `PROTOCOL` | `http` | Protocol (http or https) |
| `JMETER_HOME` | `/opt/apache-jmeter` | JMeter installation directory |

### JMeter Properties

| Property | Default | Description |
|----------|---------|-------------|
| `threads` | `1` | Number of concurrent threads (users) |
| `rampup` | `300` | Ramp-up time in seconds (5 minutes) |
| `duration` | `900` | Test duration in seconds (15 minutes) |
| `sleep_time` | `1` | Server-side sleep time in seconds |
| `payload_size` | `1024` | JSON payload size in bytes |

## Test Execution Flow

For each test scenario:

1. **Warm-up Phase** (5 minutes)
   - Threads gradually ramp up to target count
   - System stabilizes under load

2. **Test Phase** (15 minutes)
   - All threads running at full capacity
   - Metrics collected continuously

3. **Cool-down Phase** (5 minutes)
   - Allows system to stabilize
   - Ensures clean state for next test

4. **Break Phase** (5 minutes)
   - Pause between test scenarios
   - Prevents resource exhaustion

## Results

### Directory Structure

```
results/
└── YYYYMMDD-HHMMSS/
    ├── test-execution.log
    ├── summary-report.txt
    ├── test-1024b-iter1-1t/
    │   ├── results.csv
    │   ├── jmeter.log
    │   └── html-report/
    │       └── index.html
    ├── test-1024b-iter2-10t/
    │   └── ...
    └── ...
```

**Note**: All test results are saved in CSV format for easy analysis and import into spreadsheet applications.

### Viewing Results

1. **HTML Reports**:
   ```bash
   # Open in browser
   open results/YYYYMMDD-HHMMSS/test-*/html-report/index.html
   ```

2. **Summary Report**:
   ```bash
   cat results/YYYYMMDD-HHMMSS/summary-report.txt
   ```

3. **Execution Log**:
   ```bash
   tail -f results/YYYYMMDD-HHMMSS/test-execution.log
   ```

4. **CSV Files** (for further analysis):
   ```bash
   # Import into JMeter GUI for detailed analysis
   jmeter -g results/YYYYMMDD-HHMMSS/test-*/results.csv -o custom-report
   
   # Open in spreadsheet application
   open results/YYYYMMDD-HHMMSS/test-*/results.csv
   
   # Combine all results into one CSV
   cat results/YYYYMMDD-HHMMSS/test-*/results.csv > combined-results.csv
   ```

## Metrics Collected

Each test collects:
- **Response times**: Min, Max, Average, Median, 90th, 95th, 99th percentiles
- **Throughput**: Requests per second
- **Error rate**: Percentage of failed requests
- **Network**: Bytes sent/received
- **Concurrency**: Active threads over time

## Customization

### Modify Test Matrix

Edit [`run-all-tests.sh`](run-all-tests.sh:115) and update the `tests` array:

```bash
local tests=(
    "payload_size iteration threads sleep_time"
    "1024 1 1 1"
    "2048 1 5 2"
    # Add more test configurations
)
```

### Adjust Timing

Edit timing variables in [`run-all-tests.sh`](run-all-tests.sh:13):

```bash
WARMUP_TIME=300      # 5 minutes
TEST_DURATION=900    # 15 minutes
COOLDOWN_TIME=300    # 5 minutes
BREAK_TIME=300       # 5 minutes
```

### Modify Test Plan

Edit [`load-test-template.jmx`](load-test-template.jmx:1) in JMeter GUI:

```bash
jmeter -t load-test-template.jmx
```

## Monitoring During Tests

### Watch Test Progress

```bash
# Follow execution log
tail -f results/YYYYMMDD-HHMMSS/test-execution.log
```

### Monitor Target Service

```bash
# Watch pods
oc get pods -l app=rest-api-app --watch

# View HPA status
oc get hpa rest-api-app-hpa --watch

# Monitor resource usage
oc adm top pods -l app=rest-api-app

# View logs
oc logs -f deployment/rest-api-app
```

### Monitor System Resources

```bash
# CPU and Memory
top

# Network
iftop

# Disk I/O
iostat -x 5
```

## Troubleshooting

### JMeter Not Found

```bash
# Check JMeter installation
which jmeter
echo $JMETER_HOME

# Set correct path
export JMETER_HOME=/path/to/apache-jmeter
```

### Connection Refused

```bash
# Verify service is running
curl http://$HOST:$PORT/health

# Check network connectivity
ping $HOST
telnet $HOST $PORT
```

### Out of Memory

Increase JMeter heap size:

```bash
export JVM_ARGS="-Xms1g -Xmx4g"
./run-all-tests.sh
```

### Test Failures

Check individual test logs:

```bash
# View JMeter log
cat results/YYYYMMDD-HHMMSS/test-*/jmeter.log

# Check for errors
grep ERROR results/YYYYMMDD-HHMMSS/test-*/jmeter.log
```

## Best Practices

1. **Baseline Testing**: Run a single-thread test first to establish baseline performance
2. **Gradual Scaling**: Start with lower thread counts before running high-load tests
3. **Resource Monitoring**: Monitor both client and server resources during tests
4. **Result Analysis**: Review HTML reports after each test run
5. **Clean Environment**: Ensure clean state between test runs
6. **Network Stability**: Run tests from a stable network connection
7. **Sufficient Resources**: Ensure JMeter host has adequate CPU/memory

## Integration with CI/CD

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any
    stages {
        stage('Deploy Service') {
            steps {
                sh 'cd rest-api-app/openshift && ./deploy.sh'
            }
        }
        stage('Run Load Tests') {
            steps {
                sh '''
                    export HOST=$(oc get route rest-api-app -o jsonpath='{.spec.host}')
                    export PORT=443
                    export PROTOCOL=https
                    cd jmeter-tests
                    ./run-all-tests.sh
                '''
            }
        }
        stage('Archive Results') {
            steps {
                archiveArtifacts artifacts: 'jmeter-tests/results/**/*', fingerprint: true
                publishHTML([
                    reportDir: 'jmeter-tests/results',
                    reportFiles: '**/html-report/index.html',
                    reportName: 'JMeter Report'
                ])
            }
        }
    }
}
```

## Performance Targets

Expected performance characteristics:

| Threads | Payload Size | Expected TPS | Max Response Time |
|---------|--------------|--------------|-------------------|
| 1       | 1KB          | ~1 req/s     | < 1.5s           |
| 10      | 1KB          | ~10 req/s    | < 2s             |
| 100     | 1KB          | ~100 req/s   | < 3s             |
| 1000    | 1KB          | ~500 req/s   | < 5s             |

*Note: Actual performance depends on infrastructure capacity and HPA configuration*

## Support

For issues or questions:
1. Check the execution logs
2. Review JMeter documentation: https://jmeter.apache.org/
3. Verify service health and logs
4. Check OpenShift cluster resources

## License

This test suite is provided as-is for testing purposes.