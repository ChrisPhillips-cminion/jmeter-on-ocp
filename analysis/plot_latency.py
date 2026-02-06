#!/usr/bin/env python3
"""
JMeter Results Analyzer - Latency vs Thread Count by Payload Size

This script analyzes JMeter CSV results and generates a graph showing
latency per thread count with different payload sizes represented by distinct markers.

Usage:
  python plot_latency.py <csv_file> [--percentiles]
  
Options:
  --percentiles    Plot 50th, 75th, and 90th percentile lines instead of all points
"""

import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator
import numpy as np
import sys
import argparse
from pathlib import Path
from datetime import datetime


def log(message):
    """Print message with timestamp."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}")


def is_valid_thread_count(thread_count):
    """Check if thread count is one of the valid values."""
    valid_counts = [1, 2, 4, 8, 16, 32, 64, 128]
    return thread_count in valid_counts


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
    
    # Create size categories - match standard sizes
    def categorize_size(size):
        standards = [
            (1024, "1KB"),
            (4096, "4KB"),
            (51200, "50KB"),
            (204800, "200KB"),
            (1048576, "1MB"),
            (2097152, "2MB"),
            (5242880, "5MB"),
        ]
        
        # Find nearest standard size
        min_diff = float('inf')
        nearest = "1KB"
        
        for std_size, label in standards:
            diff = abs(size - std_size)
            if diff < min_diff:
                min_diff = diff
                nearest = label
        
        return nearest
    
    df['size_category'] = df['payload_size'].apply(categorize_size)
    
    # Convert timestamp to numeric
    df['timeStamp'] = pd.to_numeric(df['timeStamp'], errors='coerce')
    
    # Use elapsed time as latency (in milliseconds)
    df['latency_ms'] = pd.to_numeric(df['elapsed'], errors='coerce')
    
    # Extract thread count from allThreads column (total active threads)
    df['thread_count'] = pd.to_numeric(df['allThreads'], errors='coerce').fillna(1).astype(int)
    
    # Remove rows with invalid data
    df = df.dropna(subset=['timeStamp', 'latency_ms', 'thread_count'])
    
    # Filter to only include valid thread counts (1, 2, 4, 8, 16, 32, 64, 128)
    df = df[df['thread_count'].apply(is_valid_thread_count)]
    
    return df


def calculate_percentiles(df):
    """
    Calculate 50th, 75th, and 90th percentiles per thread count and payload size.
    """
    grouped = df.groupby(['thread_count', 'size_category'])
    
    percentile_list = []
    for (thread_count, size_cat), group in grouped:
        percentile_list.append({
            'thread_count': thread_count,
            'size_category': size_cat,
            'p50': group['latency_ms'].quantile(0.50),
            'p75': group['latency_ms'].quantile(0.75),
            'p90': group['latency_ms'].quantile(0.90),
            'sample_count': len(group)
        })
    
    return pd.DataFrame(percentile_list)


def plot_latency_graph(df, output_file='latency_analysis.png', use_percentiles=False):
    """
    Create a graph showing latency vs thread count.
    
    Args:
        df: DataFrame with raw data
        output_file: Output filename
        use_percentiles: If True, plot percentile lines; if False, plot all points
    """
    plt.figure(figsize=(14, 8))
    
    # Get unique size categories and sort them logically
    size_order = ["1KB", "4KB", "50KB", "200KB", "1MB", "2MB", "5MB"]
    size_categories = [s for s in size_order if s in df['size_category'].unique()]
    
    # Use appropriate colormap
    num_categories = len(size_categories)
    if num_categories <= 10:
        colors = plt.cm.tab10(np.linspace(0, 1, 10))
    else:
        colors = plt.cm.hsv(np.linspace(0, 1, num_categories))
    
    if use_percentiles:
        # Calculate percentiles
        log("Calculating percentiles...")
        percentiles_df = calculate_percentiles(df)
        
        # Plot percentile lines for each payload size
        for idx, size_cat in enumerate(size_categories):
            data = percentiles_df[percentiles_df['size_category'] == size_cat].sort_values('thread_count')
            
            color = colors[idx]
            
            # Plot 50th percentile (solid line)
            plt.plot(data['thread_count'], data['p50'],
                    linewidth=2,
                    color=color,
                    label=f'{size_cat}',
                    linestyle='-',
                    marker='o',
                    markersize=6)
            
            # Plot 75th percentile (dashed line, same color)
            plt.plot(data['thread_count'], data['p75'],
                    linewidth=1.5,
                    color=color,
                    linestyle='--',
                    alpha=0.7)
            
            # Plot 90th percentile (dotted line, same color)
            plt.plot(data['thread_count'], data['p90'],
                    linewidth=1.5,
                    color=color,
                    linestyle=':',
                    alpha=0.7)
        
        # Add custom legend entries for percentiles
        from matplotlib.lines import Line2D
        legend_elements = [
            Line2D([0], [0], color='gray', linewidth=2, linestyle='-', label='50th percentile'),
            Line2D([0], [0], color='gray', linewidth=1.5, linestyle='--', label='75th percentile'),
            Line2D([0], [0], color='gray', linewidth=1.5, linestyle=':', label='90th percentile')
        ]
        
        # Get existing legend
        handles, labels = plt.gca().get_legend_handles_labels()
        
        # Combine legends
        plt.legend(handles + legend_elements, labels + [e.get_label() for e in legend_elements],
                  title='Payload Size', loc='best', fontsize=9, title_fontsize=10, ncol=2)
        
        plt.title('Latency Percentiles vs Thread Count by Payload Size\n(50th, 75th, and 90th percentiles)',
                  fontsize=14, fontweight='bold', pad=20)
        log(f"✓ Plotted percentiles for {len(percentiles_df)} thread count/payload combinations")
    else:
        # Plot all individual points as scatter plot
        markers = ['o', 's', '^', 'D', 'v', 'p', '*', 'h']
        
        for idx, size_cat in enumerate(size_categories):
            data = df[df['size_category'] == size_cat]
            
            plt.scatter(data['thread_count'], data['latency_ms'],
                       marker=markers[idx % len(markers)],
                       s=20,
                       color=colors[idx],
                       label=f'{size_cat}',
                       alpha=0.6)
        
        plt.legend(title='Payload Size', loc='best', fontsize=10, title_fontsize=11)
        plt.title('Latency vs Thread Count by Payload Size\n(All individual data points)',
                  fontsize=14, fontweight='bold', pad=20)
        log(f"✓ Plotted {len(df)} individual data points")
    
    plt.xlabel('Thread Count (allThreads)', fontsize=12, fontweight='bold')
    plt.ylabel('Latency (ms)', fontsize=12, fontweight='bold')
    plt.grid(True, alpha=0.3, linestyle='--', which='both')
    
    # Get axis handle for customization
    ax = plt.gca()
    
    # Use linear scale for both axes
    ax.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, p: f'{int(x):,}'))
    ax.xaxis.set_major_locator(MaxNLocator(nbins=10, integer=True))
    
    max_threads = df['thread_count'].max()
    min_threads = df['thread_count'].min()
    log(f"Using linear axes (thread range: {min_threads}-{max_threads})")
    
    # Format axes
    plt.tight_layout()
    
    # Save the figure
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    log(f"✓ Graph saved to: {output_file}")


def main():
    """Main execution function."""
    
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description='JMeter Results Analyzer - Plot latency vs thread count',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  python plot_latency.py data.csv                  # Plot all individual points
  python plot_latency.py data.csv --percentiles    # Plot percentile lines
        '''
    )
    parser.add_argument('csv_file', help='Path to JMeter CSV results file')
    parser.add_argument('--percentiles', action='store_true',
                       help='Plot 50th, 75th, and 90th percentile lines instead of all points')
    
    args = parser.parse_args()
    
    # Validate file exists
    if not Path(args.csv_file).exists():
        log(f"Error: File not found: {args.csv_file}")
        sys.exit(1)
    
    log(f"Reading JMeter results from: {args.csv_file}")
    
    # Parse CSV
    df = parse_jmeter_csv(args.csv_file)
    log(f"✓ Loaded {len(df)} samples")
    
    # Generate output filename
    suffix = '_percentiles' if args.percentiles else '_scatter'
    output_file = Path(args.csv_file).stem + suffix + '_latency_graph.png'
    
    # Create plot
    if args.percentiles:
        log("Generating percentile line plot...")
    else:
        log("Generating scatter plot...")
    
    plot_latency_graph(df, output_file, use_percentiles=args.percentiles)
    
    log(f"\n✓ Analysis complete!")


if __name__ == "__main__":
    main()

# Made with Bob
