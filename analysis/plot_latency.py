#!/usr/bin/env python3
"""
JMeter Results Analyzer - Latency vs Thread Count by Payload Size

This script analyzes JMeter CSV results and generates a graph showing
latency per thread count with different payload sizes represented by distinct markers.
"""

import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import sys
from pathlib import Path
from datetime import datetime


def log(message):
    """Print message with timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def parse_jmeter_csv(filepath):
    """
    Parse JMeter CSV file and extract relevant metrics.
    
    Expected CSV columns (based on JMeter standard format):
    0: timeStamp
    1: elapsed (latency in ms)
    2: label
    3: responseCode
    4: responseMessage
    5: threadName
    6: dataType
    7: success
    8: failureMessage
    9: bytes
    10: sentBytes
    11: grpThreads (active threads)
    12: allThreads
    13: URL
    14: Latency
    15: IdleTime
    16: Connect
    """
    
    # Read CSV without headers since JMeter CSV doesn't have them by default
    column_names = [
        'timeStamp', 'elapsed', 'label', 'responseCode', 'responseMessage',
        'threadName', 'dataType', 'success', 'failureMessage', 'bytes',
        'sentBytes', 'grpThreads', 'allThreads', 'URL', 'Latency',
        'IdleTime', 'Connect'
    ]
    
    df = pd.read_csv(filepath, names=column_names, low_memory=False)
    
    # Extract payload size from sentBytes column (request payload size)
    # Handle NaN values and convert to int
    df['payload_size'] = pd.to_numeric(df['sentBytes'], errors='coerce').fillna(0).astype(int)
    
    # Create size categories with ranges
    def categorize_size(size):
        if size == 0:
            return '0B'
        elif size < 256:
            return '1-255B'
        elif size < 512:
            return '256-511B'
        elif size < 1024:
            return '512B-1KB'
        elif size < 2048:
            return '1-2KB'
        elif size < 4096:
            return '2-4KB'
        elif size < 8192:
            return '4-8KB'
        else:
            return '>8KB'
    
    df['size_category'] = df['payload_size'].apply(categorize_size)
    
    # Convert timestamp to numeric
    df['timeStamp'] = pd.to_numeric(df['timeStamp'], errors='coerce')
    
    # Use elapsed time as latency (in milliseconds)
    df['latency_ms'] = pd.to_numeric(df['elapsed'], errors='coerce')
    
    # Extract thread count from allThreads column (total active threads)
    df['thread_count'] = pd.to_numeric(df['allThreads'], errors='coerce').fillna(1).astype(int)
    
    # Filter to only include valid thread counts from test matrix (1, 10, 100, 1000)
    valid_thread_counts = [1, 10, 100, 1000]
    df = df[df['thread_count'].isin(valid_thread_counts)]
    
    # Remove rows with invalid data
    df = df.dropna(subset=['timeStamp', 'latency_ms', 'thread_count'])
    
    return df


def calculate_statistics(df):
    """
    Calculate TPS and average latency per thread count and payload size.
    """
    # Group by thread count and payload size
    grouped = df.groupby(['thread_count', 'size_category'])
    
    stats_list = []
    for (thread_count, size_cat), group in grouped:
        # Calculate time span in seconds
        time_span_ms = group['timeStamp'].max() - group['timeStamp'].min()
        time_span_sec = time_span_ms / 1000.0
        
        # Calculate TPS (transactions per second)
        if time_span_sec > 0:
            tps = len(group) / time_span_sec
        else:
            tps = 0
        
        # Calculate latency statistics
        stats_list.append({
            'thread_count': thread_count,
            'size_category': size_cat,
            'tps': tps,
            'mean_latency': group['latency_ms'].mean(),
            'median_latency': group['latency_ms'].median(),
            'std_latency': group['latency_ms'].std(),
            'min_latency': group['latency_ms'].min(),
            'max_latency': group['latency_ms'].max(),
            'sample_count': len(group)
        })
    
    stats = pd.DataFrame(stats_list)
    return stats


def plot_latency_graph(stats, output_file='latency_analysis.png'):
    """
    Create a graph showing latency vs thread count with different markers for payload sizes.
    """
    plt.figure(figsize=(14, 8))
    
    # Define markers and colors for different payload sizes
    markers = ['o', 's', '^', 'D', 'v', 'p', '*', 'h', 'X', 'P', '<', '>', '1', '2', '3', '4']
    
    # Get number of unique size categories
    num_categories = len(stats['size_category'].unique())
    
    # Use appropriate colormap based on number of categories
    if num_categories <= 10:
        colors = plt.cm.tab10(np.linspace(0, 1, 10))
    elif num_categories <= 20:
        colors = plt.cm.tab20(np.linspace(0, 1, 20))
    else:
        colors = plt.cm.hsv(np.linspace(0, 1, num_categories))
    
    # Get unique size categories and sort them logically
    size_order = ["1KB", "4KB", "50KB", "200KB", "1MB", "2MB", "5MB"]
    size_categories = [s for s in size_order if s in stats['size_category'].unique()]
    
    # Plot each payload size category
    for idx, size_cat in enumerate(size_categories):
        data = stats[stats['size_category'] == size_cat].sort_values('tps')
        
        plt.plot(data['tps'], data['mean_latency'],
                marker=markers[idx % len(markers)],
                markersize=8,
                linewidth=2,
                color=colors[idx],
                label=f'{size_cat}',
                alpha=0.8)
        
        # Add error bars for standard deviation (only if valid)
        # Replace NaN/inf with 0 for error bars
        std_values = data['std_latency'].fillna(0).replace([np.inf, -np.inf], 0)
        if std_values.sum() > 0:  # Only add error bars if there's valid std data
            plt.errorbar(data['tps'], data['mean_latency'],
                        yerr=std_values,
                        fmt='none',
                        ecolor=colors[idx],
                        alpha=0.3,
                        capsize=3)
        
        # Add thread count labels next to each point
        for _, row in data.iterrows():
            plt.annotate(f"{int(row['thread_count'])}",
                        xy=(row['tps'], row['mean_latency']),
                        xytext=(5, 5),
                        textcoords='offset points',
                        fontsize=8,
                        color=colors[idx],
                        alpha=0.7)
    
    plt.xlabel('Throughput (TPS - Transactions Per Second)', fontsize=12, fontweight='bold')
    plt.ylabel('Average Latency (ms)', fontsize=12, fontweight='bold')
    plt.title('Latency vs Throughput (TPS) by Payload Size\n(Error bars show standard deviation)',
              fontsize=14, fontweight='bold', pad=20)
    plt.legend(title='Payload Size', loc='best', fontsize=10, title_fontsize=11)
    plt.grid(True, alpha=0.3, linestyle='--', which='both')
    
    # Get axis handle for customization
    ax = plt.gca()
    
    # Use logarithmic scale on X-axis only if max TPS > 100000
    max_tps = stats['tps'].max()
    if max_tps > 100000:
        plt.xscale('log')
        log(f"Using logarithmic X-axis (max TPS: {max_tps:.0f})")
    else:
        # Use plain formatting for regular scale with sensible intervals
        ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'{int(x):,}'))
        # Set sensible tick intervals based on data range
        from matplotlib.ticker import MaxNLocator
        ax.xaxis.set_major_locator(MaxNLocator(nbins=10, integer=True))
        log(f"Using linear X-axis (max TPS: {max_tps:.0f})")
    
    # Set sensible Y-axis intervals
    from matplotlib.ticker import MaxNLocator
    ax.yaxis.set_major_locator(MaxNLocator(nbins=10))
    
    # Check if Y-axis (latency) needs log scale
    latency_range = stats['mean_latency'].max() / stats['mean_latency'].min() if stats['mean_latency'].min() > 0 else 1
    if latency_range > 100:
        plt.yscale('log')
        log(f"Using logarithmic Y-axis (latency range: {latency_range:.1f}x)")
    
    # Format axes
    plt.tight_layout()
    
    # Save the figure
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    log(f"✓ Graph saved to: {output_file}")
    
    # Also display summary statistics
    log("\n" + "="*70)
    log("SUMMARY STATISTICS")
    log("="*70)
    print(stats.to_string(index=False))
    log("="*70)


def main():
    """Main execution function."""
    
    # Check command line arguments
    if len(sys.argv) < 2:
        log("Usage: python plot_latency.py <path_to_csv_file>")
        log("\nExample: python plot_latency.py ../tmp/data2.csv")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    
    # Validate file exists
    if not Path(csv_file).exists():
        log(f"Error: File not found: {csv_file}")
        sys.exit(1)
    
    log(f"Reading JMeter results from: {csv_file}")
    
    # Parse CSV
    df = parse_jmeter_csv(csv_file)
    log(f"✓ Loaded {len(df)} samples")
    
    # Calculate statistics
    log("Calculating statistics...")
    stats = calculate_statistics(df)
    
    # Generate output filename
    output_file = Path(csv_file).stem + '_latency_graph.png'
    
    # Create plot
    log("Generating graph...")
    plot_latency_graph(stats, output_file)
    
    log(f"\n✓ Analysis complete!")


if __name__ == "__main__":
    main()

# Made with Bob
