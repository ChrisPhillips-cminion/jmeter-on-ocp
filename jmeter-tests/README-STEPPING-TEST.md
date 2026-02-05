# Stepping Load Test

This test configuration runs a stepping thread group that doubles the number of active threads every 2 minutes, progressing through 13 cycles from 1 to 4096 threads.

## Test Configuration

### Thread Progression
The test runs 13 steps, doubling threads at each step:
1. **Step 1**: 1 thread (0-2 min)
2. **Step 2**: 2 threads (2-4 min)
3. **Step 3**: 4 threads (4-6 min)
4. **Step 4**: 8 threads (6-8 min)
5. **Step 5**: 16 threads (8-10 min)
6. **Step 6**: 32 threads (10-12 min)
7. **Step 7**: 64 threads (12-14 min)
8. **Step 8**: 128 threads (14-16 min)
9. **Step 9**: 256 threads (16-18 min)
10. **Step 10**: 512 threads (18-20 min)
11. **Step 11**: 1024 threads (20-22 min)
12. **Step 12**: 2048 threads (22-24 min)
13. **Step 13**: 4096 threads (24-26 min)

**Total Duration**: 26 minutes per payload size

### Payload Sizes Tested
The test runs for each of these payload sizes:
- 1KB (1,024 bytes)
- 4KB (4,096 bytes)
- 50KB (51,200 bytes)
- 200KB (204,800 bytes)
- 1MB (1,048,576 bytes)
- 2MB (2,097,152 bytes)
- 5MB (5,242,880 bytes)

## Files

### Test Scripts
- **`run-stepping-test.sh`**: Main orchestration script that runs the stepping test for each payload size
- **`stepping-load-test.jmx`**: JMeter test plan with Concurrency Thread Group configured for stepping

### Key Features
1. **Automatic Thread Doubling**: Uses JMeter's Concurrency Thread Group to automatically double threads every 2 minutes
2. **Continuous Load**: Each thread continuously sends requests throughout its active period
3. **Comprehensive Metrics**: Captures timestamp, latency, thread count, and payload size for analysis
4. **Break Periods**: 30-second breaks between different payload size tests

## Usage

### Basic Usage
```bash
cd jmeter-tests
./run-stepping-test.sh
```

### Custom Configuration
```bash
# Set custom host and port
HOST=my-api.example.com PORT=8080 PROTOCOL=https ./run-stepping-test.sh

# Set custom JMeter location
JMETER_HOME=/path/to/jmeter ./run-stepping-test.sh
```

### Environment Variables
- `HOST`: Target hostname (default: 172.30.189.189)
- `PORT`: Target port (default: 8080)
- `PROTOCOL`: Protocol to use (default: http)
- `JMETER_HOME`: JMeter installation directory (default: /opt/apache-jmeter)

## Results

### Output Structure
```
results/stepping-YYYYMMDD-HHMMSS/
├── test-execution.log                    # Master execution log
├── summary-report.txt                    # Summary of all tests
├── stepping-test-1024b/                  # 1KB payload test
│   ├── results.csv                       # Raw CSV results
│   ├── jmeter.log                        # JMeter execution log
│   └── html-report/                      # HTML dashboard
│       └── index.html
├── stepping-test-4096b/                  # 4KB payload test
│   └── ...
└── ...
```

### CSV Results Format
The results CSV contains these key columns:
- `timeStamp`: Request timestamp (milliseconds)
- `elapsed`: Response time (milliseconds)
- `label`: Request label
- `responseCode`: HTTP response code
- `success`: Success/failure flag
- `bytes`: Response size
- `sentBytes`: Request size (payload)
- `allThreads`: Total active threads at time of request
- `Latency`: Request latency

## Analysis

### Using the Analysis Tools
After running the test, analyze results with the provided tools:

```bash
# Python version
python3 analysis/plot_latency.py results/stepping-YYYYMMDD-HHMMSS/stepping-test-1024b/results.csv

# Go version (faster)
./analysis-go/jmeter-analyzer results/stepping-YYYYMMDD-HHMMSS/stepping-test-1024b/results.csv
```

### Combining Results
To analyze all payload sizes together, concatenate the CSV files:

```bash
# Combine all results (skip headers after first file)
head -1 results/stepping-*/stepping-test-*/results.csv | head -1 > combined-results.csv
tail -n +2 -q results/stepping-*/stepping-test-*/results.csv >> combined-results.csv

# Analyze combined results
python3 analysis/plot_latency.py combined-results.csv
```

## Requirements

### JMeter Plugins
This test requires the **Concurrency Thread Group** plugin from the JMeter Plugins project:
- Plugin: `jpgc-casutg` (Concurrency Thread Group)
- Install via JMeter Plugins Manager or download from: https://jmeter-plugins.org/

### System Requirements
- JMeter 5.x or higher
- Java 8 or higher
- Sufficient memory (5GB heap configured via JVM_ARGS)
- Network connectivity to target API

## Advantages of Stepping Test

1. **Single Test Run**: One test captures performance across all thread counts
2. **Continuous Progression**: Smooth transition between load levels
3. **Time Efficient**: 26 minutes per payload vs. multiple separate tests
4. **Real-world Simulation**: Mimics gradual load increase scenarios
5. **Easy Analysis**: All data in one CSV file per payload size

## Comparison with Original Test

### Original Test (`run-all-tests.sh`)
- Runs 4 separate tests per payload (1, 10, 100, 1000 threads)
- Each test: 30s warmup + 5min test + 30s cooldown = 6 minutes
- Total per payload: 4 tests × 6 min = 24 minutes
- 7 payloads × 24 min = **168 minutes (2.8 hours)**

### Stepping Test (`run-stepping-test.sh`)
- Runs 1 test per payload with 13 thread levels (1→4096)
- Each test: 26 minutes continuous
- 7 payloads × 26 min = **182 minutes (3 hours)**
- **More thread levels tested** (13 vs 4)
- **Higher maximum load** (4096 vs 1000 threads)

## Notes

- The Concurrency Thread Group automatically manages thread lifecycle
- Threads ramp up smoothly to the next level at each step boundary
- Each thread runs continuously until the test ends
- Results show actual active thread count at time of each request
- Use the analysis tools to visualize latency vs thread count/TPS