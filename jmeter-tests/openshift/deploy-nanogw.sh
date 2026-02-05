#!/bin/bash

# Deployment script for JMeter Load Tests on OpenShift
# This script automates the build and deployment process

set -e

# Function to print with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "JMeter Load Tests - OpenShift Deployment"
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

# Prompt for GitHub repository URL
GITHUB_URL=https://github.com/ChrisPhillips-cminion/jmeter-on-ocp



# Prompt for branch (default: main)

BRANCH=${BRANCH:-main}

# Prompt for context directory (default: jmeter-tests)

CONTEXT_DIR=jmeter-tests

# Prompt for target service name
TARGET_SERVICE=172.30.189.189

# NanoGW configuration
NANOGW_HOST=perf-test-api-product-sandbox-chris.nanogw.apps.bubble.hur.hdclab.intranet.ibm.com
NANOGW_SERVICE=ngw-nanogw-svc.apicv12.svc.cluster.local

echo ""
log "Configuration:"
log "  GitHub URL: $GITHUB_URL"
log "  Branch: $BRANCH"
log "  Context Dir: $CONTEXT_DIR"
log "  Namespace: $CURRENT_PROJECT"
log "  Target Service: 172.30.189.189:8080"
log "  NanoGW Host: $NANOGW_HOST"
log "  NanoGW Service: $NANOGW_SERVICE"
echo ""
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    log "Deployment cancelled"
    exit 0
fi

echo ""
log "Step 1: Creating BuildConfig and ImageStream..."

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
log "Step 2: Starting build..."
oc start-build jmeter-tests --follow

echo ""
log "Step 3: Creating DeploymentConfig..."

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
            echo "Starting JMeter load tests..."
            ./run-all-tests.sh
            echo "Tests completed. Pod will remain running for result retrieval."
            echo "Results are available in /jmeter/results"
            echo "To copy results: oc rsync \$(oc get pod -l app=jmeter-tests -o name | cut -d/ -f2):/jmeter/results ./local-results"
            # Keep container running after tests complete
            tail -f /dev/null
        env:
        - name: HOST
          value: "$NANOGW_SERVICE"
        - name: PORT
          value: "443"
        - name: PROTOCOL
          value: "https"
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
log "Step 4: Waiting for deployment to be ready..."
oc rollout status dc/jmeter-tests --timeout=5m

echo ""
log "Step 5: Getting pod information..."
POD_NAME=$(oc get pod -l app=jmeter-tests -o jsonpath='{.items[0].metadata.name}')

echo ""
log "=========================================="
log "Deployment completed successfully!"
echo ""
log "JMeter tests are now running in pod: $POD_NAME"
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

# Generate sample curl request for NanoGW API
echo ""
log "=========================================="
log "Sample curl requests for NanoGW API:"
log "=========================================="
echo ""
log "# External URL (from outside the cluster):"
log "# Replace <client-id> and <client-secret> with your actual credentials"
echo ""
log "curl -X POST 'https://$NANOGW_HOST/perf/test?sleep_time=0.03' \\"
log "  -H 'Content-Type: application/json' \\"
log "  -H 'X-IBM-Client-Id: <client-id>' \\"
log "  -H 'X-IBM-Client-Secret: <client-secret>' \\"
log "  -d '{\"test\": \"data\", \"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}'"
echo ""
log "# Internal URL (from within the cluster):"
echo ""
log "curl -X POST 'https://$NANOGW_SERVICE:443/1.0.0/perf/test?sleep_time=0.03' \\"
log "  -H 'Content-Type: application/json' \\"
log "  -H 'Host: $NANOGW_HOST' \\"
log "  -d '{\"test\": \"data\", \"timestamp\": \"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'\"}' \\"
log "  -k"
echo ""
log "# Expected response:"
log "# {"
log "#   \"status\": \"success\","
log "#   \"message\": \"JSON validated and processed\","
log "#   \"sleep_time\": 0.03,"
log "#   \"payload_size\": <size>"
log "# }"
echo ""
log "# Test with different sleep times (external):"
log "curl -X POST 'https://$NANOGW_HOST/perf/test?sleep_time=0.1' \\"
log "  -H 'Content-Type: application/json' \\"
log "  -H 'X-IBM-Client-Id: <client-id>' \\"
log "  -H 'X-IBM-Client-Secret: <client-secret>' \\"
log "  -d '{\"message\": \"load test\", \"iteration\": 1}'"
echo ""
log "# Test with different sleep times (internal):"
log "curl -X POST 'https://$NANOGW_SERVICE:443/1.0.0/perf/test?sleep_time=0.1' \\"
log "  -H 'Content-Type: application/json' \\"
log "  -H 'Host: $NANOGW_HOST' \\"
log "  -d '{\"message\": \"load test\", \"iteration\": 1}' \\"
log "  -k"
echo ""
log "# Variables for easy customization:"
log "  NANOGW_HOST=$NANOGW_HOST"
log "  NANOGW_SERVICE=$NANOGW_SERVICE"
echo ""

# Made with Bob
