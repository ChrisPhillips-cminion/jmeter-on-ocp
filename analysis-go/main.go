package main

import (
	"encoding/csv"
	"flag"
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

// PercentileData holds percentile metrics per thread count and size
type PercentileData struct {
	ThreadCount  int
	SizeCategory string
	P50          float64
	P75          float64
	P90          float64
	SampleCount  int
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

func isValidThreadCount(threadCount int) bool {
	validCounts := []int{1, 2, 4, 8, 16, 32, 64, 128}
	for _, valid := range validCounts {
		if threadCount == valid {
			return true
		}
	}
	return false
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

		// Filter to only accept specific thread counts
		if !isValidThreadCount(allThreads) {
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

func calculatePercentiles(dataPoints []DataPoint) []PercentileData {
	logWithTimestamp("Calculating percentiles...")

	// Group by thread count and size category
	type groupKey struct {
		threadCount  int
		sizeCategory string
	}

	groups := make(map[groupKey][]float64)
	for _, dp := range dataPoints {
		key := groupKey{
			threadCount:  dp.AllThreads,
			sizeCategory: categorizeSize(dp.PayloadSize),
		}
		groups[key] = append(groups[key], dp.Elapsed)
	}

	var percentiles []PercentileData
	for key, latencies := range groups {
		if len(latencies) == 0 {
			continue
		}

		// Sort latencies
		sort.Float64s(latencies)

		// Calculate percentiles
		p50 := latencies[int(float64(len(latencies))*0.50)]
		p75 := latencies[int(float64(len(latencies))*0.75)]
		p90 := latencies[int(float64(len(latencies))*0.90)]

		percentiles = append(percentiles, PercentileData{
			ThreadCount:  key.threadCount,
			SizeCategory: key.sizeCategory,
			P50:          p50,
			P75:          p75,
			P90:          p90,
			SampleCount:  len(latencies),
		})
	}

	return percentiles
}

func plotGraph(dataPoints []DataPoint, outputFile string, usePercentiles bool) error {

	p := plot.New()
	p.X.Label.Text = "Thread Count (allThreads)"
	p.Y.Label.Text = "Latency (ms)"

	// Define colors
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

	sizeOrder := []string{"1KB", "4KB", "50KB", "200KB", "1MB", "2MB", "5MB"}

	if usePercentiles {
		// Calculate percentiles
		percentiles := calculatePercentiles(dataPoints)

		// Group percentiles by size category
		percentileGroups := make(map[string][]PercentileData)
		for _, pd := range percentiles {
			percentileGroups[pd.SizeCategory] = append(percentileGroups[pd.SizeCategory], pd)
		}

		// Sort each group by thread count
		for _, group := range percentileGroups {
			sort.Slice(group, func(i, j int) bool {
				return group[i].ThreadCount < group[j].ThreadCount
			})
		}

		p.Title.Text = "Latency Percentiles vs Thread Count by Payload Size\n(50th, 75th, and 90th percentiles)"

		// Plot percentile lines for each size category
		colorIdx := 0
		for _, sizeCategory := range sizeOrder {
			group, exists := percentileGroups[sizeCategory]
			if !exists || len(group) == 0 {
				continue
			}

			color := colors[colorIdx%len(colors)]

			// Create points for each percentile
			p50pts := make(plotter.XYs, len(group))
			p75pts := make(plotter.XYs, len(group))
			p90pts := make(plotter.XYs, len(group))

			for i, pd := range group {
				p50pts[i].X = float64(pd.ThreadCount)
				p50pts[i].Y = pd.P50
				p75pts[i].X = float64(pd.ThreadCount)
				p75pts[i].Y = pd.P75
				p90pts[i].X = float64(pd.ThreadCount)
				p90pts[i].Y = pd.P90
			}

			// Plot 50th percentile (solid line)
			line50, err := plotter.NewLine(p50pts)
			if err != nil {
				return err
			}
			line50.Color = color
			line50.Width = vg.Points(2)
			p.Add(line50)
			p.Legend.Add(sizeCategory, line50)

			// Plot 75th percentile (dashed line)
			line75, err := plotter.NewLine(p75pts)
			if err != nil {
				return err
			}
			line75.Color = color
			line75.Width = vg.Points(1.5)
			line75.Dashes = []vg.Length{vg.Points(5), vg.Points(2)}
			p.Add(line75)

			// Plot 90th percentile (dotted line)
			line90, err := plotter.NewLine(p90pts)
			if err != nil {
				return err
			}
			line90.Color = color
			line90.Width = vg.Points(1.5)
			line90.Dashes = []vg.Length{vg.Points(2), vg.Points(2)}
			p.Add(line90)

			colorIdx++
		}

		logWithTimestamp(fmt.Sprintf("✓ Plotted percentiles for %d thread count/payload combinations", len(percentiles)))
	} else {
		// Plot scatter points
		p.Title.Text = "Latency vs Thread Count by Payload Size\n(All individual data points)"

		// Group by size category
		sizeGroups := make(map[string][]DataPoint)
		for _, dp := range dataPoints {
			sizeCategory := categorizeSize(dp.PayloadSize)
			sizeGroups[sizeCategory] = append(sizeGroups[sizeCategory], dp)
		}

		colorIdx := 0
		for _, sizeCategory := range sizeOrder {
			group, exists := sizeGroups[sizeCategory]
			if !exists {
				continue
			}

			// Create scatter points
			pts := make(plotter.XYs, len(group))
			for i, dp := range group {
				pts[i].X = float64(dp.AllThreads)
				pts[i].Y = dp.Elapsed
			}

			scatter, err := plotter.NewScatter(pts)
			if err != nil {
				return err
			}

			scatter.Color = colors[colorIdx%len(colors)]
			scatter.Shape = draw.CircleGlyph{}
			scatter.Radius = vg.Points(2)

			p.Add(scatter)
			p.Legend.Add(sizeCategory, scatter)

			colorIdx++
		}

		logWithTimestamp(fmt.Sprintf("✓ Plotted %d individual data points", len(dataPoints)))
	}

	// Use linear scale for both axes
	var minThreads, maxThreads int = math.MaxInt32, 0
	for _, dp := range dataPoints {
		if dp.AllThreads < minThreads {
			minThreads = dp.AllThreads
		}
		if dp.AllThreads > maxThreads {
			maxThreads = dp.AllThreads
		}
	}
	logWithTimestamp(fmt.Sprintf("Using linear axes (thread range: %d-%d)", minThreads, maxThreads))

	// Position legend at top left
	p.Legend.Top = true
	p.Legend.Left = true

	// Save plot
	if err := p.Save(10*vg.Inch, 6*vg.Inch, outputFile); err != nil {
		return err
	}

	logWithTimestamp(fmt.Sprintf("✓ Graph saved to: %s", outputFile))
	return nil
}

func main() {
	// Define flags
	percentiles := flag.Bool("percentiles", false, "Plot 50th, 75th, and 90th percentile lines instead of all points")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: %s [options] <csv_file>\n\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  %s data.csv                  # Plot all individual points\n", os.Args[0])
		fmt.Fprintf(os.Stderr, "  %s -percentiles data.csv     # Plot percentile lines\n", os.Args[0])
	}
	flag.Parse()

	if flag.NArg() < 1 {
		flag.Usage()
		os.Exit(1)
	}

	csvFile := flag.Arg(0)

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

	// Generate output filename
	suffix := ""
	if *percentiles {
		suffix = "_percentiles"
	} else {
		suffix = "_scatter"
	}
	outputFile := "latency" + suffix + "_graph.png"

	// Create plot
	if err := plotGraph(dataPoints, outputFile, *percentiles); err != nil {
		log.Fatalf("Error creating plot: %v", err)
	}

	logWithTimestamp("\n✓ Analysis complete!")
}

// Made with Bob
