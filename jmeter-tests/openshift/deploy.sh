#!/bin/bash

# Deployment script for JMeter Load Tests on OpenShift
# This script automates the build and deployment process

set -e

echo "JMeter Load Tests - OpenShift Deployment"
echo "=========================================="
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

# Set target namespace
NAMESPACE=jmeter

# Check if namespace exists, create if it doesn't
if ! oc get namespace $NAMESPACE &> /dev/null; then
    echo "Namespace '$NAMESPACE' does not exist. Creating it..."
    oc create namespace $NAMESPACE
    echo "Namespace '$NAMESPACE' created successfully"
else
    echo "Namespace '$NAMESPACE' already exists"
fi

# Switch to the namespace
oc project $NAMESPACE
CURRENT_PROJECT=$NAMESPACE
echo "Current OpenShift project: $CURRENT_PROJECT"
echo ""

# Prompt for GitHub repository URL
GITHUB_URL=https://github.com/ChrisPhillips-cminion/jmeter-on-ocp



# Prompt for branch (default: main)

BRANCH=${BRANCH:-main}

# Prompt for context directory (default: jmeter-tests)

CONTEXT_DIR=jmeter-tests

# Prompt for target service name
TARGET_SERVICE=172.30.189.189

echo ""
echo "Configuration:"
echo "  GitHub URL: $GITHUB_URL"
echo "  Branch: $BRANCH"
echo "  Context Dir: $CONTEXT_DIR"
echo "  Namespace: $CURRENT_PROJECT"
echo "  Target Service: 172.30.189.189:8080"
echo ""
read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Step 1: Creating BuildConfig and ImageStream..."

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
echo "Step 2: Starting build..."
oc start-build jmeter-tests --follow

echo ""
echo "Step 3: Creating DeploymentConfig..."

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
          value: "$TARGET_SERVICE"
        - name: PORT
          value: "8080"
        - name: PROTOCOL
          value: "http"
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
echo "Step 4: Waiting for deployment to be ready..."
oc rollout status dc/jmeter-tests --timeout=5m

echo ""
echo "Step 5: Getting pod information..."
POD_NAME=$(oc get pod -l app=jmeter-tests -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "=========================================="
echo "Deployment completed successfully!"
echo ""
echo "JMeter tests are now running in pod: $POD_NAME"
echo ""
echo "Monitor test progress:"
echo "  oc logs -f $POD_NAME"
echo ""
echo "Check pod status:"
echo "  oc get pod $POD_NAME"
echo ""
echo "Once tests complete, retrieve results:"
echo "  oc rsync $POD_NAME:/jmeter/results ./local-results"
echo ""
echo "View results in pod:"
echo "  oc exec $POD_NAME -- ls -lh /jmeter/results"
echo ""
echo "Delete deployment when done:"
echo "  oc delete dc jmeter-tests"
echo "  oc delete service jmeter-tests"
echo "  oc delete bc jmeter-tests"
echo "  oc delete is jmeter-tests"
echo ""

# Cleanup temp files
rm -f /tmp/jmeter-buildconfig-temp.yaml /tmp/jmeter-deployment-temp.yaml

echo "GitHub Webhook URL (for automatic builds):"
oc describe bc jmeter-tests | grep -A 1 "Webhook GitHub" || echo "  Run: oc describe bc jmeter-tests"
echo ""

# Made with Bob
