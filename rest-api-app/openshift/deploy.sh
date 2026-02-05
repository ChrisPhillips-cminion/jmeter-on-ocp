#!/bin/bash

# Deployment script for REST API App on OpenShift
# This script automates the build and deployment process for the high-performance Go REST API
# Usage: ./deploy.sh [-y|--yes] [--skip-build]
#   -y, --yes        Accept all defaults without prompting
#   --skip-build     Skip the build step and only deploy

set -e

# Function to print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Parse command line arguments
ACCEPT_DEFAULTS=false
SKIP_BUILD=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            ACCEPT_DEFAULTS=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        *)
            log "Unknown option: $1"
            log "Usage: $0 [-y|--yes] [--skip-build]"
            exit 1
            ;;
    esac
done

log "REST API App - OpenShift Deployment"
log "===================================="
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

# Set defaults
DEFAULT_GITHUB_URL="https://github.com/ChrisPhillips-cminion/jmeter-on-ocp"
DEFAULT_BRANCH="main"
DEFAULT_CONTEXT_DIR="rest-api-app"

if [ "$ACCEPT_DEFAULTS" = true ]; then
    # Use defaults without prompting
    GITHUB_URL=$DEFAULT_GITHUB_URL
    BRANCH=$DEFAULT_BRANCH
    CONTEXT_DIR=$DEFAULT_CONTEXT_DIR
    log "Using default configuration"
else
    # Prompt for configuration
    read -p "Enter GitHub repository URL [$DEFAULT_GITHUB_URL]: " GITHUB_URL
    GITHUB_URL=${GITHUB_URL:-$DEFAULT_GITHUB_URL}

    read -p "Enter branch name [$DEFAULT_BRANCH]: " BRANCH
    BRANCH=${BRANCH:-$DEFAULT_BRANCH}

    read -p "Enter context directory [$DEFAULT_CONTEXT_DIR]: " CONTEXT_DIR
    CONTEXT_DIR=${CONTEXT_DIR:-$DEFAULT_CONTEXT_DIR}
fi

echo ""
log "Configuration:"
log "  GitHub URL: $GITHUB_URL"
log "  Branch: $BRANCH"
log "  Context Dir: $CONTEXT_DIR"
log "  Namespace: $CURRENT_PROJECT"
echo ""

if [ "$ACCEPT_DEFAULTS" = false ]; then
    read -p "Continue with deployment? (y/n): " CONFIRM
    if [ "$CONFIRM" != "y" ]; then
        log "Deployment cancelled"
        exit 0
    fi
fi

if [ "$SKIP_BUILD" = false ]; then
    echo ""
    log "Step 1: Creating BuildConfig and ImageStream..."

    # Create BuildConfig and ImageStream
cat > /tmp/rest-api-buildconfig-temp.yaml <<'EOF'
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
      uri: GITHUB_URL_PLACEHOLDER
      ref: BRANCH_PLACEHOLDER
    contextDir: CONTEXT_DIR_PLACEHOLDER
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

# Replace placeholders with actual values
gsed -i "s|GITHUB_URL_PLACEHOLDER|$GITHUB_URL|g" /tmp/rest-api-buildconfig-temp.yaml
gsed -i "s|BRANCH_PLACEHOLDER|$BRANCH|g" /tmp/rest-api-buildconfig-temp.yaml
gsed -i "s|CONTEXT_DIR_PLACEHOLDER|$CONTEXT_DIR|g" /tmp/rest-api-buildconfig-temp.yaml

    oc apply -f /tmp/rest-api-buildconfig-temp.yaml

    echo ""
    log "Step 2: Starting build..."
    oc start-build rest-api-app --follow
    
    # Cleanup temp files
    rm -f /tmp/rest-api-buildconfig-temp.yaml
else
    log "Skipping build step (--skip-build flag set)"
fi

echo ""
log "Step 3: Deploying DeploymentConfig..."

# Apply the DeploymentConfig (script is run from openshift directory)
oc apply -f deployment.yaml

echo ""
log "Step 4: Waiting for deployment to be ready..."
oc rollout status dc/rest-api-app --timeout=5m

echo ""
log "Step 5: Getting service information..."
ROUTE_HOST=$(oc get route rest-api-app -o jsonpath='{.spec.host}' 2>/dev/null || echo "No route found")
SERVICE_IP=$(oc get service rest-api-app -o jsonpath='{.spec.clusterIP}')

echo ""
log "===================================="
log "Deployment completed successfully!"
echo ""
log "Service Information:"
log "  Service IP: $SERVICE_IP"
log "  Service Port: 8080"
if [ "$ROUTE_HOST" != "No route found" ]; then
    log "  External URL: https://$ROUTE_HOST"
fi
echo ""
log "Test the API:"
log "  Health check:"
log "    curl http://$SERVICE_IP:8080/health"
if [ "$ROUTE_HOST" != "No route found" ]; then
    log "    curl https://$ROUTE_HOST/health"
fi
echo ""
log "  Process endpoint:"
log "    curl -X POST 'http://$SERVICE_IP:8080/api/process?sleep_time=0.03' \\"
log "      -H 'Content-Type: application/json' \\"
log "      -d '{\"test\": \"data\"}'"
echo ""
log "Monitor pods:"
log "  oc get pods -l app=rest-api-app"
echo ""
log "View logs:"
log "  oc logs -f dc/rest-api-app"
echo ""
log "Scale deployment:"
log "  oc scale dc/rest-api-app --replicas=4"
echo ""
log "Delete deployment when done:"
log "  oc delete dc rest-api-app"
log "  oc delete service rest-api-app"
log "  oc delete route rest-api-app"
log "  oc delete bc rest-api-app"
log "  oc delete is rest-api-app"
echo ""

if [ "$SKIP_BUILD" = false ]; then
    log "GitHub Webhook URL (for automatic builds):"
    oc describe bc rest-api-app | grep -A 1 "Webhook GitHub" || log "  Run: oc describe bc rest-api-app"
    echo ""
fi

# Made with Bob
