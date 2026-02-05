# JMeter Results Analyzer

This tool analyzes JMeter CSV results and generates a graph showing latency per thread count with different payload sizes represented by distinct icons/markers.

## Features

- **Latency Analysis**: Plots average latency against thread count (concurrent users)
- **Payload Size Differentiation**: Each payload size category has its own marker style
- **Statistical Visualization**: Includes error bars showing standard deviation
- **Summary Statistics**: Displays detailed statistics table

## Installation

1. Install Python dependencies:

```bash
pip install -r requirements.txt
```

Or install individually:

```bash
pip install pandas matplotlib numpy
```

## Usage

Run the script with your JMeter CSV file:

```bash
python plot_latency.py <path_to_csv_file>
```

### Example

```bash
python plot_latency.py ../tmp/data2.csv
```

This will:
1. Parse the JMeter CSV results
2. Calculate statistics grouped by thread count and payload size
3. Generate a graph saved as `data2_latency_graph.png`
4. Display summary statistics in the console

## Output

### Graph Features

- **X-axis**: Thread Count (Concurrent Users)
- **Y-axis**: Average Latency (milliseconds)
- **Markers**: Different shapes for each payload size category:
  - Circle (○): < 500B
  - Square (□): 500B-1KB
  - Triangle (△): 1KB-5KB
  - Diamond (◇): 5KB-10KB
  - Inverted Triangle (▽): > 10KB
- **Error Bars**: Show standard deviation for each data point
- **Legend**: Identifies each payload size category

### Payload Size Categories

The script automatically categorizes response sizes into:
- `< 500B`: Less than 500 bytes
- `500B-1KB`: 500 bytes to 1 kilobyte
- `1KB-5KB`: 1 to 5 kilobytes
- `5KB-10KB`: 5 to 10 kilobytes
- `> 10KB`: Greater than 10 kilobytes

## CSV Format

The script expects JMeter CSV output with the following columns (standard JMeter format):

```
timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Latency,IdleTime,Connect
```

Key columns used:
- `elapsed`: Response time (latency) in milliseconds
- `bytes`: Response payload size in bytes
- `grpThreads`: Number of active threads (concurrent users)

## Example Output

```
Reading JMeter results from: ../tmp/data2.csv
✓ Loaded 16687091 samples
Calculating statistics...
Generating graph...
✓ Graph saved to: data2_latency_graph.png

======================================================================
SUMMARY STATISTICS
======================================================================
   thread_count size_category  mean_latency  median_latency  std_latency  ...
              1       500B-1KB         33.45           33.0         1.23  ...
              1       1KB-5KB          34.12           34.0         2.45  ...
...
======================================================================

✓ Analysis complete!
```

## Troubleshooting

### Import Errors

If you see import errors, ensure all dependencies are installed:

```bash
pip install --upgrade pandas matplotlib numpy
```

### File Not Found

Ensure the CSV file path is correct and the file exists:

```bash
ls -la ../tmp/data2.csv
```

### Memory Issues

For very large CSV files (millions of rows), the script may require significant memory. Consider:
- Using a machine with more RAM
- Sampling the data before analysis
- Processing the file in chunks

## Customization

You can modify the script to:
- Change payload size categories (edit `categorize_size()` function)
- Adjust marker styles and colors (edit `plot_latency_graph()` function)
- Add additional metrics (modify `calculate_statistics()` function)
- Change graph styling (update matplotlib parameters)

## License

This tool is provided as-is for analyzing JMeter performance test results.