package main

import (
	"encoding/csv"
	"fmt"
	"image/color"
	"io"
	"log"
	"math"
	"os"
	"sort"
	"strconv"
	"time"

	"gonum.org/v1/plot"
	"gonum.org/v1/plot/plotter"
	"gonum.org/v1/plot/vg"
	"gonum.org/v1/plot/vg/draw"
)

// DataPoint represents a single JMeter result
type DataPoint struct {
	TimeStamp   int64
	Elapsed     float64
	SentBytes   int
	AllThreads  int
	PayloadSize int
}

// Statistics holds aggregated metrics
type Statistics struct {
	ThreadCount   int
	SizeCategory  string
	TPS           float64
	MeanLatency   float64
	MedianLatency float64
	StdLatency    float64
	MinLatency    float64
	MaxLatency    float64
	SampleCount   int
}

func logWithTimestamp(message string) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	fmt.Printf("[%s] %s\n", timestamp, message)
}

func categorizeSize(size int) string {
	// Standard sizes in bytes
	standards := []struct {
		size  int
		label string
	}{
		{1024, "1KB"},
		{4096, "4KB"},
		{51200, "50KB"},
		{204800, "200KB"},
		{1048576, "1MB"},
		{2097152, "2MB"},
		{5242880, "5MB"},
	}

	// Find nearest standard size
	minDiff := int(^uint(0) >> 1) // Max int
	nearest := "1KB"

	for _, std := range standards {
		diff := size - std.size
		if diff < 0 {
			diff = -diff
		}
		if diff < minDiff {
			minDiff = diff
			nearest = std.label
		}
	}

	return nearest
}

func parseCSV(filename string) ([]DataPoint, error) {
	logWithTimestamp(fmt.Sprintf("Reading JMeter results from: %s", filename))

	file, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	reader := csv.NewReader(file)
	reader.FieldsPerRecord = -1 // Allow variable number of fields

	var dataPoints []DataPoint
	validThreadCounts := map[int]bool{1: true, 10: true, 100: true, 1000: true}

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			continue // Skip malformed lines
		}

		if len(record) < 13 {
			continue
		}

		// Parse fields
		timeStamp, err1 := strconv.ParseInt(record[0], 10, 64)
		elapsed, err2 := strconv.ParseFloat(record[1], 64)
		sentBytes, err3 := strconv.Atoi(record[10])
		allThreads, err4 := strconv.Atoi(record[12])

		if err1 != nil || err2 != nil || err3 != nil || err4 != nil {
			continue
		}

		// Filter to valid thread counts
		if !validThreadCounts[allThreads] {
			continue
		}

		dataPoints = append(dataPoints, DataPoint{
			TimeStamp:   timeStamp,
			Elapsed:     elapsed,
			SentBytes:   sentBytes,
			AllThreads:  allThreads,
			PayloadSize: sentBytes,
		})
	}

	logWithTimestamp(fmt.Sprintf("✓ Loaded %d samples", len(dataPoints)))
	return dataPoints, nil
}

func calculateStatistics(dataPoints []DataPoint) []Statistics {
	logWithTimestamp("Calculating statistics...")

	// Group by thread count and size category
	type groupKey struct {
		threadCount  int
		sizeCategory string
	}

	groups := make(map[groupKey][]DataPoint)
	for _, dp := range dataPoints {
		key := groupKey{
			threadCount:  dp.AllThreads,
			sizeCategory: categorizeSize(dp.PayloadSize),
		}
		groups[key] = append(groups[key], dp)
	}

	var stats []Statistics
	for key, group := range groups {
		if len(group) == 0 {
			continue
		}

		// Calculate time span
		var minTime, maxTime int64 = math.MaxInt64, 0
		var latencies []float64
		var sumLatency float64

		for _, dp := range group {
			if dp.TimeStamp < minTime {
				minTime = dp.TimeStamp
			}
			if dp.TimeStamp > maxTime {
				maxTime = dp.TimeStamp
			}
			latencies = append(latencies, dp.Elapsed)
			sumLatency += dp.Elapsed
		}

		timeSpanSec := float64(maxTime-minTime) / 1000.0
		tps := 0.0
		if timeSpanSec > 0 {
			tps = float64(len(group)) / timeSpanSec
		}

		// Calculate statistics
		meanLatency := sumLatency / float64(len(group))

		// Median
		sort.Float64s(latencies)
		medianLatency := latencies[len(latencies)/2]

		// Standard deviation
		var variance float64
		for _, lat := range latencies {
			diff := lat - meanLatency
			variance += diff * diff
		}
		stdLatency := math.Sqrt(variance / float64(len(group)))

		stats = append(stats, Statistics{
			ThreadCount:   key.threadCount,
			SizeCategory:  key.sizeCategory,
			TPS:           tps,
			MeanLatency:   meanLatency,
			MedianLatency: medianLatency,
			StdLatency:    stdLatency,
			MinLatency:    latencies[0],
			MaxLatency:    latencies[len(latencies)-1],
			SampleCount:   len(group),
		})
	}

	return stats
}

func plotGraph(stats []Statistics, outputFile string) error {
	logWithTimestamp("Generating graph...")

	p := plot.New()
	p.Title.Text = "Latency vs Throughput (TPS) by Payload Size"
	p.X.Label.Text = "Throughput (TPS - Transactions Per Second)"
	p.Y.Label.Text = "Average Latency (ms)"

	// Group by size category
	sizeOrder := []string{"1KB", "4KB", "50KB", "200KB", "1MB", "2MB", "5MB"}
	sizeGroups := make(map[string][]Statistics)
	for _, stat := range stats {
		sizeGroups[stat.SizeCategory] = append(sizeGroups[stat.SizeCategory], stat)
	}

	// Plot each size category
	colors := []color.RGBA{
		{R: 31, G: 119, B: 180, A: 255},
		{R: 255, G: 127, B: 14, A: 255},
		{R: 44, G: 160, B: 44, A: 255},
		{R: 214, G: 39, B: 40, A: 255},
		{R: 148, G: 103, B: 189, A: 255},
		{R: 140, G: 86, B: 75, A: 255},
		{R: 227, G: 119, B: 194, A: 255},
		{R: 127, G: 127, B: 127, A: 255},
	}

	colorIdx := 0
	for _, sizeCategory := range sizeOrder {
		group, exists := sizeGroups[sizeCategory]
		if !exists {
			continue
		}

		// Sort by TPS
		sort.Slice(group, func(i, j int) bool {
			return group[i].TPS < group[j].TPS
		})

		// Create points and error bars
		pts := make(plotter.XYs, len(group))
		errs := make(plotter.YErrors, len(group))
		for i, stat := range group {
			pts[i].X = stat.TPS
			pts[i].Y = stat.MeanLatency
			// Use standard deviation for error bars
			errs[i].Low = stat.StdLatency
			errs[i].High = stat.StdLatency
		}

		line, points, err := plotter.NewLinePoints(pts)
		if err != nil {
			return err
		}

		line.Color = colors[colorIdx%len(colors)]
		points.Color = colors[colorIdx%len(colors)]
		points.Shape = draw.CircleGlyph{}

		// Add error bars for standard deviation
		errBars, err := plotter.NewYErrorBars(struct {
			plotter.XYer
			plotter.YErrorer
		}{pts, errs})
		if err == nil {
			errBars.Color = colors[colorIdx%len(colors)]
			errBars.LineStyle.Width = vg.Points(0.5)
			p.Add(errBars)
		}

		p.Add(line, points)
		p.Legend.Add(sizeCategory, line, points)

		// Add thread count labels next to each point
		for _, stat := range group {
			label, err := plotter.NewLabels(plotter.XYLabels{
				XYs:    []plotter.XY{{X: stat.TPS, Y: stat.MeanLatency}},
				Labels: []string{fmt.Sprintf("%d", stat.ThreadCount)},
			})
			if err == nil {
				for i := range label.TextStyle {
					label.TextStyle[i].Color = colors[colorIdx%len(colors)]
					label.TextStyle[i].Font.Size = vg.Points(8)
				}
				p.Add(label)
			}
		}

		colorIdx++
	}

	// Use logarithmic scale on X-axis only if max TPS > 100000
	var maxTPS float64 = 0
	for _, stat := range stats {
		if stat.TPS > maxTPS {
			maxTPS = stat.TPS
		}
	}

	if maxTPS > 100000 {
		p.X.Scale = plot.LogScale{}
		p.X.Tick.Marker = plot.LogTicks{}
		logWithTimestamp(fmt.Sprintf("Using logarithmic X-axis (max TPS: %.0f)", maxTPS))
	} else {
		logWithTimestamp(fmt.Sprintf("Using linear X-axis (max TPS: %.0f)", maxTPS))
	}

	// Check if Y-axis (latency) needs log scale
	var minLat, maxLat float64 = math.MaxFloat64, 0
	for _, stat := range stats {
		if stat.MeanLatency > 0 && stat.MeanLatency < minLat {
			minLat = stat.MeanLatency
		}
		if stat.MeanLatency > maxLat {
			maxLat = stat.MeanLatency
		}
	}

	if minLat > 0 && maxLat/minLat > 100 {
		p.Y.Scale = plot.LogScale{}
		p.Y.Tick.Marker = plot.LogTicks{}
		logWithTimestamp(fmt.Sprintf("Using logarithmic Y-axis (latency range: %.1fx)", maxLat/minLat))
	}

	// Save plot
	if err := p.Save(10*vg.Inch, 6*vg.Inch, outputFile); err != nil {
		return err
	}

	logWithTimestamp(fmt.Sprintf("✓ Graph saved to: %s", outputFile))
	return nil
}

func printStatistics(stats []Statistics) {
	logWithTimestamp("\n" + "======================================================================")
	logWithTimestamp("SUMMARY STATISTICS")
	logWithTimestamp("======================================================================")

	fmt.Printf("%-12s %-15s %-10s %-12s %-12s %-10s\n",
		"ThreadCount", "SizeCategory", "TPS", "MeanLatency", "StdLatency", "Samples")
	fmt.Println("----------------------------------------------------------------------")

	for _, stat := range stats {
		fmt.Printf("%-12d %-15s %-10.2f %-12.2f %-12.2f %-10d\n",
			stat.ThreadCount, stat.SizeCategory, stat.TPS,
			stat.MeanLatency, stat.StdLatency, stat.SampleCount)
	}

	logWithTimestamp("======================================================================")
}

func main() {
	if len(os.Args) < 2 {
		logWithTimestamp("Usage: go run main.go <path_to_csv_file>")
		logWithTimestamp("\nExample: go run main.go ../tmp/data2.csv")
		os.Exit(1)
	}

	csvFile := os.Args[1]

	// Check if file exists
	if _, err := os.Stat(csvFile); os.IsNotExist(err) {
		logWithTimestamp(fmt.Sprintf("Error: File not found: %s", csvFile))
		os.Exit(1)
	}

	// Parse CSV
	dataPoints, err := parseCSV(csvFile)
	if err != nil {
		log.Fatalf("Error parsing CSV: %v", err)
	}

	// Calculate statistics
	stats := calculateStatistics(dataPoints)

	// Generate output filename
	outputFile := "latency_graph.png"

	// Create plot
	if err := plotGraph(stats, outputFile); err != nil {
		log.Fatalf("Error creating plot: %v", err)
	}

	// Print statistics
	printStatistics(stats)

	logWithTimestamp("\n✓ Analysis complete!")
}

// Made with Bob
