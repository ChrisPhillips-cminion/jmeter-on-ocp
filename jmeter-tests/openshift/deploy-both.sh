#!/bin/bash

# Deployment script for JMeter Load Tests on OpenShift
# This script runs tests against both non-NanoGW and NanoGW endpoints in sequence

set -e

# Function to print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "JMeter Load Tests - OpenShift Deployment (Both Endpoints)"
log "=========================================="
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

# Set target namespace
NAMESPACE=jmeter

# Check if namespace exists, create if it doesn't
if ! oc get namespace $NAMESPACE &> /dev/null; then
    log "Namespace '$NAMESPACE' does not exist. Creating it..."
    oc create namespace $NAMESPACE
    log "Namespace '$NAMESPACE' created successfully"
else
    log "Namespace '$NAMESPACE' already exists"
fi

# Switch to the namespace
oc project $NAMESPACE
CURRENT_PROJECT=$NAMESPACE
log "Current OpenShift project: $CURRENT_PROJECT"
echo ""

# Configuration
GITHUB_URL=https://github.com/ChrisPhillips-cminion/jmeter-on-ocp
BRANCH=${BRANCH:-main}
CONTEXT_DIR=jmeter-tests

# Target endpoints
DIRECT_SERVICE=172.30.189.189
NANOGW_HOST=perf-test-api-product-sandbox-chris.nanogw.apps.bubble.hur.hdclab.intranet.ibm.com
NANOGW_SERVICE=ngw-nanogw-svc.apicv12.svc.cluster.local

echo ""
log "Configuration:"
log "  GitHub URL: $GITHUB_URL"
log "  Branch: $BRANCH"
log "  Context Dir: $CONTEXT_DIR"
log "  Namespace: $CURRENT_PROJECT"
log "  Direct Service: $DIRECT_SERVICE:8080"
log "  NanoGW Host: $NANOGW_HOST"
log "  NanoGW Service: $NANOGW_SERVICE:443"
echo ""
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    log "Deployment cancelled"
    exit 0
fi

echo ""
log "Step 1: Cleaning up existing deployment (if any)..."
if oc get dc jmeter-tests &> /dev/null; then
    log "Deleting existing DeploymentConfig..."
    oc delete dc jmeter-tests --ignore-not-found=true
    log "Waiting for pods to terminate..."
    oc wait --for=delete pod -l app=jmeter-tests --timeout=60s 2>/dev/null || true
fi

echo ""
log "Step 2: Creating BuildConfig and ImageStream..."

# Create temporary buildconfig with substituted values
cat > /tmp/jmeter-buildconfig-temp.yaml << EOF
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: jmeter-tests
  labels:
    app: jmeter-tests
spec:
  output:
    to:
      kind: ImageStreamTag
      name: jmeter-tests:latest
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
  name: jmeter-tests
  labels:
    app: jmeter-tests
spec:
  lookupPolicy:
    local: false
EOF

oc apply -f /tmp/jmeter-buildconfig-temp.yaml

echo ""
log "Step 3: Starting build..."
if ! oc start-build jmeter-tests --follow; then
    log "ERROR: Build failed! Stopping deployment."
    exit 1
fi
log "Build completed successfully"

echo ""
log "Step 4: Creating DeploymentConfig..."

# Create temporary deployment with substituted values
cat > /tmp/jmeter-deployment-temp.yaml << EOF
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: jmeter-tests
  namespace: $NAMESPACE
  labels:
    app: jmeter-tests
spec:
  replicas: 1
  selector:
    app: jmeter-tests
  template:
    metadata:
      labels:
        app: jmeter-tests
    spec:
      containers:
      - name: jmeter-tests
        image: jmeter-tests:latest
        command: ["/bin/bash"]
        args:
          - "-c"
          - |
            echo "=========================================="
            echo "JMeter Stepping Load Tests - Both Endpoints"
            echo "=========================================="
            echo ""
            
            # Test 1: Direct endpoint (non-NanoGW)
            echo "Phase 1: Testing Direct Endpoint"
            echo "Target: $DIRECT_SERVICE:8080"
            echo "=========================================="
            export HOST="$DIRECT_SERVICE"
            export PORT="8080"
            export PROTOCOL="http"
            ./run-stepping-test.sh
            
            echo ""
            echo "=========================================="
            echo "Phase 1 Complete - Direct Endpoint"
            echo "=========================================="
            echo ""
            echo "Waiting 60 seconds before starting Phase 2..."
            sleep 60
            echo ""
            
            # Test 2: NanoGW endpoint
            echo "Phase 2: Testing NanoGW Endpoint"
            echo "Target: $NANOGW_SERVICE:443"
            echo "=========================================="
            export HOST="$NANOGW_SERVICE"
            export PORT="443"
            export PROTOCOL="https"
            ./run-stepping-test.sh
            
            echo ""
            echo "=========================================="
            echo "All Tests Completed!"
            echo "=========================================="
            echo "Results are available in /jmeter/results"
            echo "To copy results: oc rsync \$(oc get pod -l app=jmeter-tests -o name | cut -d/ -f2):/jmeter/results ./local-results"
            echo ""
            
            # Keep container running after tests complete
            tail -f /dev/null
        env:
        - name: DIRECT_SERVICE
          value: "$DIRECT_SERVICE"
        - name: NANOGW_SERVICE
          value: "$NANOGW_SERVICE"
        - name: NANOGW_HOST
          value: "$NANOGW_HOST"
        - name: JMETER_HOME
          value: "/opt/apache-jmeter"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        volumeMounts:
        - name: results
          mountPath: /jmeter/results
      volumes:
      - name: results
        emptyDir: {}
  triggers:
  - type: ConfigChange
  - type: ImageChange
    imageChangeParams:
      automatic: true
      containerNames:
      - jmeter-tests
      from:
        kind: ImageStreamTag
        name: jmeter-tests:latest
---
apiVersion: v1
kind: Service
metadata:
  name: jmeter-tests
  namespace: $NAMESPACE
  labels:
    app: jmeter-tests
spec:
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app: jmeter-tests
  type: ClusterIP
EOF

oc apply -f /tmp/jmeter-deployment-temp.yaml

echo ""
log "Step 5: Waiting for deployment to be ready..."
oc rollout status dc/jmeter-tests --timeout=5m

echo ""
log "Step 6: Getting pod information..."
POD_NAME=$(oc get pod -l app=jmeter-tests -o jsonpath='{.items[0].metadata.name}')

echo ""
log "=========================================="
log "Deployment completed successfully!"
echo ""
log "JMeter tests are now running in pod: $POD_NAME"
echo ""
log "Test Sequence:"
log "  1. Direct endpoint: $DIRECT_SERVICE:8080 (http)"
log "  2. NanoGW endpoint: $NANOGW_SERVICE:443 (https)"
echo ""
log "Monitor test progress:"
log "  oc logs -f $POD_NAME"
echo ""
log "Check pod status:"
log "  oc get pod $POD_NAME"
echo ""
log "Once tests complete, retrieve results:"
log "  oc rsync $POD_NAME:/jmeter/results ./local-results"
echo ""
log "View results in pod:"
log "  oc exec $POD_NAME -- ls -lh /jmeter/results"
echo ""
log "Delete deployment when done:"
log "  oc delete dc jmeter-tests"
log "  oc delete service jmeter-tests"
log "  oc delete bc jmeter-tests"
log "  oc delete is jmeter-tests"
echo ""

# Cleanup temp files
rm -f /tmp/jmeter-buildconfig-temp.yaml /tmp/jmeter-deployment-temp.yaml

log "GitHub Webhook URL (for automatic builds):"
oc describe bc jmeter-tests | grep -A 1 "Webhook GitHub" || log "  Run: oc describe bc jmeter-tests"
echo ""

log "=========================================="
log "Test Duration Estimate:"
log "  Phase 1 (Direct): ~3 hours (7 payloads × 26 min)"
log "  Break: 1 minute"
log "  Phase 2 (NanoGW): ~3 hours (7 payloads × 26 min)"
log "  Total: ~6 hours"
log "=========================================="
echo ""

# Made with Bob
