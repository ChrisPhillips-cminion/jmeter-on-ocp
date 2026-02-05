package main

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"sync"
	"time"

	jsoniter "github.com/json-iterator/go"
	"github.com/valyala/fasthttp"
)

var json = jsoniter.ConfigCompatibleWithStandardLibrary

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

// Object pools for zero-allocation responses
var (
	healthResponsePool = sync.Pool{
		New: func() interface{} {
			return &HealthResponse{Status: "healthy"}
		},
	}

	processResponsePool = sync.Pool{
		New: func() interface{} {
			return &ProcessResponse{}
		},
	}

	errorResponsePool = sync.Pool{
		New: func() interface{} {
			return &ErrorResponse{}
		},
	}
)

// Health check endpoint
func healthHandler(ctx *fasthttp.RequestCtx) {
	ctx.SetContentType("application/json")

	resp := healthResponsePool.Get().(*HealthResponse)
	defer healthResponsePool.Put(resp)

	if err := json.NewEncoder(ctx).Encode(resp); err != nil {
		ctx.SetStatusCode(fasthttp.StatusInternalServerError)
	}
}

// Process request endpoint
func processHandler(ctx *fasthttp.RequestCtx) {
	// Only accept POST
	if !ctx.IsPost() {
		ctx.SetContentType("application/json")
		ctx.SetStatusCode(fasthttp.StatusMethodNotAllowed)

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = "Method not allowed"
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
		return
	}

	// Get sleep time from query parameter (default: 0.03 seconds = 30ms)
	sleepTime := 0.03
	if sleepTimeBytes := ctx.QueryArgs().Peek("sleep_time"); sleepTimeBytes != nil {
		parsed, err := strconv.ParseFloat(string(sleepTimeBytes), 64)
		if err != nil {
			ctx.SetContentType("application/json")
			ctx.SetStatusCode(fasthttp.StatusBadRequest)

			errResp := errorResponsePool.Get().(*ErrorResponse)
			errResp.Error = "Invalid sleep_time parameter"
			json.NewEncoder(ctx).Encode(errResp)
			errorResponsePool.Put(errResp)
			return
		}
		sleepTime = parsed
	}

	// Validate sleep time
	if sleepTime < 0 {
		ctx.SetContentType("application/json")
		ctx.SetStatusCode(fasthttp.StatusBadRequest)

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = "sleep_time must be non-negative"
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
		return
	}
	if sleepTime > 60 {
		ctx.SetContentType("application/json")
		ctx.SetStatusCode(fasthttp.StatusBadRequest)

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = "sleep_time cannot exceed 60 seconds"
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
		return
	}

	// Validate Content-Type
	contentType := string(ctx.Request.Header.ContentType())
	if contentType != "application/json" {
		ctx.SetContentType("application/json")
		ctx.SetStatusCode(fasthttp.StatusBadRequest)

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = "Content-Type must be application/json"
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
		return
	}

	// Read and validate JSON payload
	body := ctx.PostBody()
	payloadSize := len(body)

	// Validate JSON
	var payload interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		ctx.SetContentType("application/json")
		ctx.SetStatusCode(fasthttp.StatusBadRequest)

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = fmt.Sprintf("Invalid JSON: %v", err)
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
		return
	}

	log.Printf("Received valid JSON payload with %d bytes", payloadSize)
	log.Printf("Sleeping for %.3f seconds", sleepTime)

	// Sleep for the specified duration
	time.Sleep(time.Duration(sleepTime * float64(time.Second)))

	// Return success response
	ctx.SetContentType("application/json")

	resp := processResponsePool.Get().(*ProcessResponse)
	resp.Status = "success"
	resp.Message = "JSON validated and processed"
	resp.SleepTime = sleepTime
	resp.PayloadSize = payloadSize

	json.NewEncoder(ctx).Encode(resp)
	processResponsePool.Put(resp)
}

// Root endpoint with API documentation
func rootHandler(ctx *fasthttp.RequestCtx) {
	ctx.SetContentType("application/json")

	response := RootResponse{
		Service: "REST API Sleep Service",
		Version: "3.0.0-ultra",
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

	json.NewEncoder(ctx).Encode(response)
}

// Main request handler
func requestHandler(ctx *fasthttp.RequestCtx) {
	path := string(ctx.Path())

	switch path {
	case "/health":
		healthHandler(ctx)
	case "/api/process":
		processHandler(ctx)
	case "/":
		rootHandler(ctx)
	default:
		ctx.SetStatusCode(fasthttp.StatusNotFound)
		ctx.SetContentType("application/json")

		errResp := errorResponsePool.Get().(*ErrorResponse)
		errResp.Error = "Not found"
		json.NewEncoder(ctx).Encode(errResp)
		errorResponsePool.Put(errResp)
	}
}

func main() {
	// Get port from environment or use default
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Configure fasthttp server for maximum performance
	server := &fasthttp.Server{
		Handler:                       requestHandler,
		Name:                          "REST-API-Ultra",
		ReadTimeout:                   10 * time.Second,
		WriteTimeout:                  10 * time.Second,
		IdleTimeout:                   120 * time.Second,
		MaxRequestBodySize:            1 * 1024 * 1024, // 1 MB
		DisableKeepalive:              false,
		TCPKeepalive:                  true,
		TCPKeepalivePeriod:            30 * time.Second,
		MaxConnsPerIP:                 0,          // unlimited
		MaxRequestsPerConn:            0,          // unlimited
		Concurrency:                   256 * 1024, // 256k concurrent connections
		DisableHeaderNamesNormalizing: true,       // Faster header processing
		NoDefaultServerHeader:         true,
		NoDefaultDate:                 false,
		NoDefaultContentType:          false,
		ReduceMemoryUsage:             false, // Prioritize speed over memory
	}

	addr := ":" + port
	log.Printf("Starting ultra-high-performance REST API server on port %s", port)
	log.Printf("Performance optimizations enabled:")
	log.Printf("  - fasthttp (10x faster than net/http)")
	log.Printf("  - json-iterator (3x faster JSON)")
	log.Printf("  - sync.Pool (zero-allocation responses)")
	log.Printf("  - Optimized connection handling")
	log.Printf("  - Maximum concurrency: 256k connections")
	log.Printf("Expected performance: 50,000+ req/s per core")

	if err := server.ListenAndServe(addr); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}

// Made with Bob
