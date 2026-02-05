.PHONY: setup build run clean

# Setup dependencies
setup:
	@echo "Setting up Go dependencies..."
	go mod tidy
	go mod download
	@echo "✓ Dependencies installed"

# Build the binary
build: setup
	@echo "Building jmeter-analyzer..."
	go build -o jmeter-analyzer main.go
	@echo "✓ Build complete: ./jmeter-analyzer"

# Build optimized binary
build-optimized: setup
	@echo "Building optimized jmeter-analyzer..."
	go build -ldflags="-s -w" -o jmeter-analyzer main.go
	@echo "✓ Optimized build complete: ./jmeter-analyzer"

# Run with example file
run: build
	@echo "Running analyzer..."
	./jmeter-analyzer ../tmp/data2.csv

# Clean build artifacts
clean:
	@echo "Cleaning..."
	rm -f jmeter-analyzer
	@echo "✓ Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  make setup           - Download and setup dependencies"
	@echo "  make build           - Build the binary"
	@echo "  make build-optimized - Build optimized binary (smaller size)"
	@echo "  make run             - Build and run with example file"
	@echo "  make clean           - Remove build artifacts"
	@echo "  make help            - Show this help message"