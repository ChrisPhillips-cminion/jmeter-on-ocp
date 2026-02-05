#!/bin/bash

# Deployment script for NanoGW Performance Test API
# This script deploys the API definition to IBM API Connect NanoGW

set -e

# Function to print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "NanoGW Performance Test API - Deployment"
log "========================================="
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    log "Error: OpenShift CLI (oc) is not installed or not in PATH"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    log "Error: Not logged in to OpenShift. Please run 'oc login' first"
    exit 1
fi

# Get current project
CURRENT_PROJECT=$(oc project -q)
log "Current OpenShift project: $CURRENT_PROJECT"
echo ""

# Prompt for namespace (default: apicv12)
read -p "Enter target namespace [apicv12]: " NAMESPACE
NAMESPACE=${NAMESPACE:-apicv12}

# Check if namespace exists
if ! oc get namespace $NAMESPACE &> /dev/null; then
    log "Error: Namespace '$NAMESPACE' does not exist"
    log "Please create the namespace first or use an existing one"
    exit 1
fi

# Switch to the namespace if different
if [ "$CURRENT_PROJECT" != "$NAMESPACE" ]; then
    oc project $NAMESPACE
    log "Switched to namespace: $NAMESPACE"
fi

echo ""
log "Configuration:"
log "  Namespace: $NAMESPACE"
log "  API Name: perf-test-api"
log "  Endpoint: POST /perf/test"
log "  Backend: http://172.30.189.189:8080/api/process"
echo ""

read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    log "Deployment cancelled"
    exit 0
fi

echo ""
log "Step 1: Creating ConfigMap with OpenAPI definition..."
oc apply -f configmap.yaml

echo ""
log "Step 2: Creating API custom resource..."
oc apply -f api.yaml

echo ""
log "Step 3: Waiting for API to be ready..."
sleep 5

# Check API status
API_STATUS=$(oc get api perf-test-api -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
log "API Status: $API_STATUS"

echo ""
log "========================================="
log "Deployment completed successfully!"
echo ""
log "API Information:"
log "  Name: perf-test-api"
log "  Namespace: $NAMESPACE"
log "  Endpoint: POST /perf/test"
echo ""
log "Test the API:"
log "  Get API details:"
log "    oc get api perf-test-api -oyaml"
echo ""
log "  Get API status:"
log "    oc describe api perf-test-api"
echo ""
log "  Example curl command (replace with actual gateway URL and credentials):"
log "    curl -X POST 'https://<gateway-url>/perf/test?sleep_time=0.03' \\"
log "      -H 'Content-Type: application/json' \\"
log "      -H 'X-IBM-Client-Id: <client-id>' \\"
log "      -H 'X-IBM-Client-Secret: <client-secret>' \\"
log "      -d '{\"test\": \"data\"}'"
echo ""
log "Delete API when done:"
log "  oc delete api perf-test-api"
log "  oc delete configmap perf-test-api-openapi"
echo ""

# Made with Bob