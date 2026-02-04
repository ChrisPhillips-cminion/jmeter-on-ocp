#!/bin/bash

# Test script for REST API Sleep Service
# Usage: ./test_api.sh [base_url]

BASE_URL=${1:-"http://localhost:8080"}

echo "Testing REST API Sleep Service at: $BASE_URL"
echo "================================================"
echo ""

# Test 1: Health check
echo "Test 1: Health Check"
echo "--------------------"
curl -s "$BASE_URL/health" | jq .
echo -e "\n"

# Test 2: Root endpoint
echo "Test 2: Root Documentation"
echo "--------------------------"
curl -s "$BASE_URL/" | jq .
echo -e "\n"

# Test 3: Valid JSON with no sleep
echo "Test 3: Valid JSON (no sleep)"
echo "-----------------------------"
curl -s -X POST "$BASE_URL/api/process" \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "key": "value"}' | jq .
echo -e "\n"

# Test 4: Valid JSON with 2 second sleep
echo "Test 4: Valid JSON (2 second sleep)"
echo "-----------------------------------"
START=$(date +%s)
curl -s -X POST "$BASE_URL/api/process?sleep_time=2" \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' | jq .
END=$(date +%s)
DURATION=$((END - START))
echo "Actual duration: ${DURATION}s"
echo -e "\n"

# Test 5: Invalid JSON
echo "Test 5: Invalid JSON"
echo "--------------------"
curl -s -X POST "$BASE_URL/api/process?sleep_time=1" \
  -H "Content-Type: application/json" \
  -d '{invalid json}' | jq .
echo -e "\n"

# Test 6: Missing Content-Type
echo "Test 6: Missing Content-Type"
echo "-----------------------------"
curl -s -X POST "$BASE_URL/api/process?sleep_time=1" \
  -d '{"test": "data"}' | jq .
echo -e "\n"

# Test 7: Negative sleep time
echo "Test 7: Negative sleep time"
echo "---------------------------"
curl -s -X POST "$BASE_URL/api/process?sleep_time=-1" \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' | jq .
echo -e "\n"

# Test 8: Excessive sleep time
echo "Test 8: Excessive sleep time (>60s)"
echo "------------------------------------"
curl -s -X POST "$BASE_URL/api/process?sleep_time=100" \
  -H "Content-Type: application/json" \
  -d '{"test": "data"}' | jq .
echo -e "\n"

echo "================================================"
echo "All tests completed!"

# Made with Bob
