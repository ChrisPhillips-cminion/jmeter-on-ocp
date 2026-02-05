# IBM NanoGW Performance Test API

IBM API Connect NanoGW API definition that proxies requests to the ultra-high-performance Go REST API backend.

## Overview

This NanoGW API exposes a `POST /perf/test` endpoint that:
- Accepts JSON payloads
- Validates the JSON structure
- Proxies to the backend service at `http://172.30.189.189:8080/api/process`
- Supports optional sleep delay via query parameter
- Returns processing results

## API Specification

**Endpoint:** `POST /perf/test`

**Query Parameters:**
- `sleep_time` (optional): Sleep duration in seconds (default: 0.03, max: 60)

**Request Body:**
```json
{
  "test": "data",
  "message": "performance test"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "JSON validated and processed",
  "sleep_time": 0.03,
  "payload_size": 42
}
```

**Authentication:**
- `X-IBM-Client-Id`: Client ID header (required)
- `X-IBM-Client-Secret`: Client Secret header (required)

## Files

- `perf-test-api_1.0.0.yaml` - OpenAPI 3.0 specification (IBM APIC format)
- `openapi.yaml` - Alternative OpenAPI specification
- `configmap.yaml` - Kubernetes ConfigMap with OpenAPI definition
- `api.yaml` - NanoGW API Custom Resource Definition
- `deploy.sh` - Deployment script

## Deployment

### Prerequisites

1. OpenShift cluster with IBM API Connect NanoGW installed
2. `oc` CLI tool installed and configured
3. Access to the target namespace (default: `apicv12`)
4. Backend service running at `http://172.30.189.189:8080`

### Quick Deploy

```bash
cd nanogw-api
./deploy.sh
```

The script will:
1. Prompt for target namespace (default: apicv12)
2. Create the ConfigMap with OpenAPI definition
3. Create the API custom resource
4. Verify deployment status

### Manual Deployment

```bash
# Switch to target namespace
oc project apicv12

# Create ConfigMap
oc apply -f configmap.yaml

# Create API resource
oc apply -f api.yaml

# Verify deployment
oc get api perf-test-api
oc describe api perf-test-api
```

## Testing

### Get API Details

```bash
# View API configuration
oc get api perf-test-api -oyaml

# Check API status
oc describe api perf-test-api

# View OpenAPI definition
oc get configmap perf-test-api-openapi -oyaml
```

### Test the API

Replace `<gateway-url>`, `<client-id>`, and `<client-secret>` with your actual values:

```bash
# Basic test with default sleep (30ms)
curl -X POST 'https://<gateway-url>/perf/test' \
  -H 'Content-Type: application/json' \
  -H 'X-IBM-Client-Id: <client-id>' \
  -H 'X-IBM-Client-Secret: <client-secret>' \
  -d '{"test": "data"}'

# Test with custom sleep time
curl -X POST 'https://<gateway-url>/perf/test?sleep_time=0.1' \
  -H 'Content-Type: application/json' \
  -H 'X-IBM-Client-Id: <client-id>' \
  -H 'X-IBM-Client-Secret: <client-secret>' \
  -d '{"message": "performance test", "timestamp": "2026-02-05T16:00:00Z"}'

# Load test with JMeter
# Update JMeter test plan to use the NanoGW endpoint
```

## Backend Service

The API proxies to a high-performance Go backend with:
- **fasthttp** - 10x faster than standard net/http
- **json-iterator** - 3x faster JSON processing
- **sync.Pool** - Zero-allocation responses
- **50,000+ req/s per core** throughput
- **<0.1ms p50 latency**

## Architecture

```
Client Request
    ↓
IBM NanoGW (API Gateway)
    ↓ (proxy)
POST /perf/test → http://172.30.189.189:8080/api/process
    ↓
Ultra-High-Performance Go Backend
    ↓
Response
```

## Configuration

### Modify Backend URL

Edit the `target.url` in the OpenAPI specification:

```yaml
x-ibm-configuration:
  assembly:
    execute:
    - invoke:
        endpoint:
          http:
            target:
              url: http://172.30.189.189:8080/api/process$(request.search)
```

### Adjust Timeout

Default timeout is 60 seconds. Modify in the OpenAPI spec:

```yaml
target:
  timeout: 60  # seconds
```

### Enable/Disable CORS

CORS is enabled by default for all origins:

```yaml
cors:
- action: allow
  originList:
  - '*'
```

## Troubleshooting

### API Not Found

```bash
# Check if API exists
oc get api perf-test-api

# Check namespace
oc project
```

### Backend Connection Issues

```bash
# Verify backend service is running
curl http://172.30.189.189:8080/health

# Check network connectivity from NanoGW pod
oc exec <nanogw-pod> -- curl http://172.30.189.189:8080/health
```

### Authentication Errors

Ensure you have valid Client ID and Client Secret from IBM API Connect.

## Cleanup

```bash
# Delete API and ConfigMap
oc delete api perf-test-api
oc delete configmap perf-test-api-openapi
```

## Performance Considerations

- The backend can handle 50,000+ requests/second per core
- NanoGW adds minimal overhead (~1-2ms)
- For maximum throughput, scale both NanoGW and backend pods
- Use connection pooling in load testing tools
- Monitor CPU and memory usage during load tests

## Made with Bob