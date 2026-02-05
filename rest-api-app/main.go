package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"
)

// Response structures
type HealthResponse struct {
	Status string `json:"status"`
}

type ProcessResponse struct {
	Status      string  `json:"status"`
	Message     string  `json:"message"`
	SleepTime   float64 `json:"sleep_time"`
	PayloadSize int     `json:"payload_size"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

type RootResponse struct {
	Service   string                 `json:"service"`
	Version   string                 `json:"version"`
	Endpoints map[string]string      `json:"endpoints"`
	Usage     map[string]interface{} `json:"usage"`
}

// Health check endpoint
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(HealthResponse{Status: "healthy"})
}

// Process request endpoint
func processHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "Method not allowed"})
		return
	}

	// Get sleep time from query parameter (default: 0.03 seconds = 30ms)
	sleepTimeStr := r.URL.Query().Get("sleep_time")
	sleepTime := 0.03
	if sleepTimeStr != "" {
		parsed, err := strconv.ParseFloat(sleepTimeStr, 64)
		if err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(ErrorResponse{Error: "Invalid sleep_time parameter"})
			return
		}
		sleepTime = parsed
	}

	// Validate sleep time
	if sleepTime < 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "sleep_time must be non-negative"})
		return
	}
	if sleepTime > 60 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "sleep_time cannot exceed 60 seconds"})
		return
	}

	// Validate Content-Type
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "Content-Type must be application/json"})
		return
	}

	// Read and validate JSON payload
	body, err := io.ReadAll(r.Body)
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: "Failed to read request body"})
		return
	}
	defer r.Body.Close()

	// Validate JSON
	var payload interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(ErrorResponse{Error: fmt.Sprintf("Invalid JSON: %v", err)})
		return
	}

	payloadSize := len(body)
	log.Printf("Received valid JSON payload with %d bytes", payloadSize)
	log.Printf("Sleeping for %.3f seconds", sleepTime)

	// Sleep for the specified duration
	time.Sleep(time.Duration(sleepTime * float64(time.Second)))

	// Return success response
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ProcessResponse{
		Status:      "success",
		Message:     "JSON validated and processed",
		SleepTime:   sleepTime,
		PayloadSize: payloadSize,
	})
}

// Root endpoint with API documentation
func rootHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	response := RootResponse{
		Service: "REST API Sleep Service",
		Version: "2.0.0",
		Endpoints: map[string]string{
			"/health":      "GET - Health check",
			"/api/process": "POST - Process JSON payload with optional sleep",
			"/":            "GET - This documentation",
		},
		Usage: map[string]interface{}{
			"endpoint":     "/api/process?sleep_time=5",
			"method":       "POST",
			"content_type": "application/json",
			"example": map[string]string{
				"curl": `curl -X POST 'http://localhost:8080/api/process?sleep_time=2' -H 'Content-Type: application/json' -d '{"test": "data"}'`,
			},
		},
	}

	json.NewEncoder(w).Encode(response)
}

func main() {
	// Set up routes
	http.HandleFunc("/health", healthHandler)
	http.HandleFunc("/api/process", processHandler)
	http.HandleFunc("/", rootHandler)

	// Get port from environment or use default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Configure server for high performance
	server := &http.Server{
		Addr:           ":" + port,
		Handler:        http.DefaultServeMux,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		IdleTimeout:    120 * time.Second,
		MaxHeaderBytes: 1 << 20, // 1 MB
	}

	log.Printf("Starting high-performance REST API server on port %s", port)
	log.Printf("Performance optimizations enabled:")
	log.Printf("  - Native Go HTTP server (no framework overhead)")
	log.Printf("  - Efficient JSON encoding/decoding")
	log.Printf("  - Optimized timeouts and connection handling")
	log.Printf("  - Low memory footprint")

	if err := server.ListenAndServe(); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// Made with Bob
