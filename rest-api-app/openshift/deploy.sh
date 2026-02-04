#!/bin/bash

# Deployment script for REST API Sleep Service on OpenShift
# This script automates the deployment process

set -e

echo "REST API Sleep Service - OpenShift Deployment"
echo "=============================================="
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
GITHUB_URL=https://github.com/ChrisPhillips-cminion/jmeter-on-ocp
if [ -z "$GITHUB_URL" ]; then
    echo "Error: GitHub URL is required"
    exit 1
fi

# Prompt for branch (default: main)
BRANCH=main

# Prompt for context directory (default: rest-api-app)
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
echo "Step 1: Creating temporary configuration files..."

# Create temporary buildconfig with substituted values
cat > /tmp/buildconfig-temp.yaml << EOF
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

# Create temporary deployment with substituted namespace
cat > /tmp/deployment-temp.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rest-api-app
  labels:
    app: rest-api-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: rest-api-app
  template:
    metadata:
      labels:
        app: rest-api-app
    spec:
      containers:
      - name: rest-api-app
        image: image-registry.openshift-image-registry.svc:5000/$CURRENT_PROJECT/rest-api-app:latest
        ports:
        - containerPort: 8080
          protocol: TCP
        env:
        - name: FLASK_ENV
          value: "production"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
---
apiVersion: v1
kind: Service
metadata:
  name: rest-api-app
  labels:
    app: rest-api-app
spec:
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  selector:
    app: rest-api-app
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: rest-api-app
  labels:
    app: rest-api-app
spec:
  to:
    kind: Service
    name: rest-api-app
    weight: 100
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
EOF

echo "Step 2: Creating BuildConfig and ImageStream..."
oc apply -f /tmp/buildconfig-temp.yaml

echo ""
echo "Step 3: Starting build..."
oc start-build rest-api-app --follow

echo ""
echo "Step 4: Deploying application..."
oc apply -f /tmp/deployment-temp.yaml

echo ""
echo "Step 5: Waiting for deployment to be ready..."
oc rollout status deployment/rest-api-app --timeout=5m

echo ""
echo "Step 6: Creating HorizontalPodAutoscaler..."
oc apply -f "$(dirname "$0")/hpa.yaml"

echo ""
echo "Step 7: Getting route URL..."
ROUTE_URL=$(oc get route rest-api-app -o jsonpath='{.spec.host}')

echo ""
echo "=============================================="
echo "Deployment completed successfully!"
echo ""
echo "HPA Status:"
oc get hpa rest-api-app-hpa
echo ""
echo "Application URL: https://$ROUTE_URL"
echo ""
echo "Test the deployment:"
echo "  curl https://$ROUTE_URL/health"
echo "  curl -X POST 'https://$ROUTE_URL/api/process?sleep_time=2' \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"test\": \"data\"}'"
echo ""
echo "View logs:"
echo "  oc logs -f deployment/rest-api-app"
echo ""
echo "Scale deployment:"
echo "  oc scale deployment/rest-api-app --replicas=5"
echo ""

# Cleanup temp files
rm -f /tmp/buildconfig-temp.yaml /tmp/deployment-temp.yaml

echo "GitHub Webhook URL (for automatic builds):"
oc describe bc rest-api-app | grep -A 1 "Webhook GitHub" || echo "  Run: oc describe bc rest-api-app"
echo ""

# Made with Bob
