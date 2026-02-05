# Multi-stage build for minimal image size and maximum performance
FROM golang:1.21-alpine AS builder

WORKDIR /build

# Copy source code and go mod files
COPY go.mod go.sum main.go ./

# Build with optimizations
# -ldflags="-s -w" strips debug info for smaller binary
# CGO_ENABLED=0 for static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -o rest-api-app \
    main.go

# Final stage - minimal runtime image
FROM scratch

# Copy CA certificates for HTTPS (if needed)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the binary
COPY --from=builder /build/rest-api-app /rest-api-app

# Expose port
EXPOSE 8080

# Set environment
ENV PORT=8080

# Run as non-root user (UID 1001 for OpenShift compatibility)
USER 1001

# Run the application
ENTRYPOINT ["/rest-api-app"]

# Made with Bob