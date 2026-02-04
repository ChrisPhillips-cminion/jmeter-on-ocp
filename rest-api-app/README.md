# REST API Sleep Service

A simple Python Flask REST API that validates JSON payloads and sleeps for a specified duration. Designed for load testing with JMeter on OpenShift/Kubernetes.

## Features

- **JSON Validation**: Validates incoming JSON payloads
- **Configurable Sleep**: Sleep duration controlled via query parameter
- **Health Check**: `/health` endpoint for liveness/readiness probes
- **Production Ready**: Uses Gunicorn with multiple workers
- **OpenShift Compatible**: Runs on port 8080 with proper health checks

## API Endpoints

### `GET /`
Returns API documentation and usage examples.

### `GET /health`
Health check endpoint for monitoring.

**Response:**
```json
{
  "status": "healthy"
}
```

### `POST /api/process?sleep_time=<seconds>`
Process JSON payload and sleep for specified duration.

**Query Parameters:**
- `sleep_time` (optional): Sleep duration in seconds (0-60, default: 0)

**Request:**
```bash
curl -X POST 'http://localhost:8080/api/process?sleep_time=2' \
  -H 'Content-Type: application/json' \
  -d '{"test": "data", "key": "value"}'
```

**Response:**
```json
{
  "status": "success",
  "message": "JSON validated and processed",
  "sleep_time": 2.0,
  "payload_size": 28
}
```

## Local Development

### Prerequisites
- Python 3.11+
- pip

### Setup
```bash
cd rest-api-app
pip install -r requirements.txt
python app.py
```

The service will start on `http://localhost:8080`

### Test Locally
```bash
# Health check
curl http://localhost:8080/health

# Process request with 2 second sleep
curl -X POST 'http://localhost:8080/api/process?sleep_time=2' \
  -H 'Content-Type: application/json' \
  -d '{"test": "data"}'
```

## Docker Build

```bash
cd rest-api-app
docker build -t rest-api-app:latest .
docker run -p 8080:8080 rest-api-app:latest
```

## OpenShift Deployment

### Prerequisites
- OpenShift CLI (`oc`) installed and configured
- Access to an OpenShift cluster
- GitHub repository with this code

### Step 1: Update Configuration

Edit `openshift/buildconfig.yaml` and replace:
- `YOUR_USERNAME/YOUR_REPO_NAME` with your GitHub repository
- Adjust `ref: main` if using a different branch

Edit `openshift/deployment.yaml` and replace:
- `YOUR_NAMESPACE` with your OpenShift project/namespace

### Step 2: Create OpenShift Resources

```bash
# Login to OpenShift
oc login <your-cluster-url>

# Create or switch to your project
oc new-project rest-api-app
# OR
oc project rest-api-app

# Create BuildConfig and ImageStream
oc apply -f openshift/buildconfig.yaml

# Start the build
oc start-build rest-api-app --follow

# Deploy the application
oc apply -f openshift/deployment.yaml
```

### Step 3: Get the Route URL

```bash
oc get route rest-api-app
```

The output will show your application URL (e.g., `https://rest-api-app-your-namespace.apps.cluster.example.com`)

### Step 4: Test the Deployment

```bash
# Get the route URL
ROUTE_URL=$(oc get route rest-api-app -o jsonpath='{.spec.host}')

# Test health endpoint
curl https://$ROUTE_URL/health

# Test API endpoint
curl -X POST "https://$ROUTE_URL/api/process?sleep_time=1" \
  -H 'Content-Type: application/json' \
  -d '{"test": "data"}'
```

## GitHub Webhook (Optional)

To enable automatic builds on git push:

1. Get the webhook URL:
```bash
oc describe bc rest-api-app | grep -A 1 "Webhook GitHub"
```

2. In your GitHub repository:
   - Go to Settings → Webhooks → Add webhook
   - Paste the webhook URL
   - Set Content type to `application/json`
   - Select "Just the push event"
   - Click "Add webhook"

## JMeter Integration

This service is designed to work with JMeter for load testing. Example JMeter HTTP Request configuration:

- **Server Name**: `${__P(host,rest-api-app-your-namespace.apps.cluster.example.com)}`
- **Port**: `443` (or `80` for non-TLS)
- **Protocol**: `https` (or `http`)
- **Method**: `POST`
- **Path**: `/api/process?sleep_time=2`
- **Body Data**: `{"test": "data", "timestamp": "${__time()}"}`
- **Headers**: `Content-Type: application/json`

## Horizontal Pod Autoscaling (HPA)

The application includes HPA configuration for automatic scaling based on resource utilization:

**HPA Configuration:**
- **Min Replicas**: 2
- **Max Replicas**: 10
- **CPU Target**: 70% utilization
- **Memory Target**: 80% utilization

**Scale-Up Behavior:**
- Immediate response (0s stabilization)
- Can scale up by 100% or add 4 pods per 30 seconds (whichever is higher)

**Scale-Down Behavior:**
- 5-minute stabilization window to prevent flapping
- Can scale down by 50% or remove 2 pods per 60 seconds (whichever is lower)

**Apply HPA:**
```bash
oc apply -f openshift/hpa.yaml
```

**Monitor HPA:**
```bash
# View HPA status
oc get hpa rest-api-app-hpa

# Watch HPA in real-time
oc get hpa rest-api-app-hpa --watch

# Detailed HPA information
oc describe hpa rest-api-app-hpa
```

**Note**: Ensure metrics-server is installed in your cluster for HPA to function. Most OpenShift clusters have this by default.

## Monitoring

View logs:
```bash
oc logs -f deployment/rest-api-app
```

Check pod status:
```bash
oc get pods -l app=rest-api-app
```

Manual scaling (if not using HPA):
```bash
oc scale deployment/rest-api-app --replicas=5
```

View resource usage:
```bash
oc adm top pods -l app=rest-api-app
```

## Resource Limits

Default resource configuration:
- **Requests**: 128Mi memory, 100m CPU
- **Limits**: 512Mi memory, 500m CPU
- **Initial Replicas**: 2
- **HPA Range**: 2-10 replicas (auto-scaling enabled)

Adjust in `openshift/deployment.yaml` and `openshift/hpa.yaml` as needed for your load testing requirements.

## Troubleshooting

### Build fails
```bash
oc logs -f bc/rest-api-app
```

### Pod not starting
```bash
oc describe pod <pod-name>
oc logs <pod-name>
```

### Route not accessible
```bash
oc get route rest-api-app
oc describe route rest-api-app
```

## License

This project is provided as-is for testing purposes.