#!/bin/bash

# Deployment script for REST API App on OpenShift
# This script automates the build and deployment process for the high-performance Go REST API

set -e

echo "REST API App - OpenShift Deployment"
echo "===================================="
echo ""

# Check if oc is installed
if ! command -v oc &> /dev/null; then
    echo "Error: OpenShift CLI (oc) is not installed or not in PATH"
    exit 1
fi

# Check if logged in to OpenShift
if ! oc whoami &> /dev/null; then
    echo "Error: Not logged in to OpenShift. Please run 'oc login' first"
    exit 1
fi

# Get current project
CURRENT_PROJECT=$(oc project -q)
echo "Current OpenShift project: $CURRENT_PROJECT"
echo ""

# Prompt for GitHub repository URL
read -p "Enter GitHub repository URL [https://github.com/ChrisPhillips-cminion/jmeter-on-ocp]: " GITHUB_URL
GITHUB_URL=${GITHUB_URL:-https://github.com/ChrisPhillips-cminion/jmeter-on-ocp}

# Prompt for branch (default: main)
read -p "Enter branch name [main]: " BRANCH
BRANCH=${BRANCH:-main}

# Prompt for context directory (default: rest-api-app)
read -p "Enter context directory [rest-api-app]: " CONTEXT_DIR
CONTEXT_DIR=${CONTEXT_DIR:-rest-api-app}

echo ""
echo "Configuration:"
echo "  GitHub URL: $GITHUB_URL"
echo "  Branch: $BRANCH"
echo "  Context Dir: $CONTEXT_DIR"
echo "  Namespace: $CURRENT_PROJECT"
echo ""
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Step 1: Creating BuildConfig and ImageStream..."

# Create BuildConfig and ImageStream
cat > /tmp/rest-api-buildconfig-temp.yaml << EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: rest-api-app
  labels:
    app: rest-api-app
spec:
  output:
    to:
      kind: ImageStreamTag
      name: rest-api-app:latest
  source:
    type: Git
    git:
      uri: $GITHUB_URL
      ref: $BRANCH
    contextDir: $CONTEXT_DIR
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  triggers:
    - type: ConfigChange
    - type: GitHub
      github:
        secret: github-webhook-secret
    - type: Generic
      generic:
        secret: generic-webhook-secret
---
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: rest-api-app
  labels:
    app: rest-api-app
spec:
  lookupPolicy:
    local: false
EOF

oc apply -f /tmp/rest-api-buildconfig-temp.yaml

echo ""
echo "Step 2: Starting build..."
oc start-build rest-api-app --follow

echo ""
echo "Step 3: Deploying DeploymentConfig..."

# Apply the DeploymentConfig from the openshift directory
oc apply -f openshift/deployment.yaml

echo ""
echo "Step 4: Waiting for deployment to be ready..."
oc rollout status dc/rest-api-app --timeout=5m

echo ""
echo "Step 5: Getting service information..."
ROUTE_HOST=$(oc get route rest-api-app -o jsonpath='{.spec.host}' 2>/dev/null || echo "No route found")
SERVICE_IP=$(oc get service rest-api-app -o jsonpath='{.spec.clusterIP}')

echo ""
echo "===================================="
echo "Deployment completed successfully!"
echo ""
echo "Service Information:"
echo "  Service IP: $SERVICE_IP"
echo "  Service Port: 8080"
if [ "$ROUTE_HOST" != "No route found" ]; then
    echo "  External URL: https://$ROUTE_HOST"
fi
echo ""
echo "Test the API:"
echo "  Health check:"
echo "    curl http://$SERVICE_IP:8080/health"
if [ "$ROUTE_HOST" != "No route found" ]; then
    echo "    curl https://$ROUTE_HOST/health"
fi
echo ""
echo "  Process endpoint:"
echo "    curl -X POST 'http://$SERVICE_IP:8080/api/process?sleep_time=0.03' \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"test\": \"data\"}'"
echo ""
echo "Monitor pods:"
echo "  oc get pods -l app=rest-api-app"
echo ""
echo "View logs:"
echo "  oc logs -f dc/rest-api-app"
echo ""
echo "Scale deployment:"
echo "  oc scale dc/rest-api-app --replicas=4"
echo ""
echo "Delete deployment when done:"
echo "  oc delete dc rest-api-app"
echo "  oc delete service rest-api-app"
echo "  oc delete route rest-api-app"
echo "  oc delete bc rest-api-app"
echo "  oc delete is rest-api-app"
echo ""

# Cleanup temp files
rm -f /tmp/rest-api-buildconfig-temp.yaml

echo "GitHub Webhook URL (for automatic builds):"
oc describe bc rest-api-app | grep -A 1 "Webhook GitHub" || echo "  Run: oc describe bc rest-api-app"
echo ""

# Made with Bob
