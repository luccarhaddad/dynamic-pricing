#!/bin/bash

echo "🧪 Testing SSE Connections"
echo "=========================="
echo ""

# Test 1: Check if API is running
echo "Test 1: Health Check"
echo "--------------------"
HEALTH=$(curl -s http://localhost:8081/api/v1/health)
if [ $? -eq 0 ]; then
    echo "✓ API is running"
    echo "Response: $HEALTH" | jq '.' 2>/dev/null || echo "Response: $HEALTH"
else
    echo "✗ API is not running"
    exit 1
fi
echo ""

# Test 2: Check regular price endpoint
echo "Test 2: Get Zone 1 Price"
echo "------------------------"
PRICE=$(curl -s http://localhost:8081/api/v1/zones/1/price)
if [ $? -eq 0 ]; then
    echo "✓ Price endpoint working"
    echo "Response: $PRICE" | jq '.' 2>/dev/null || echo "Response: $PRICE"
else
    echo "✗ Price endpoint failed"
fi
echo ""

# Test 3: Test SSE connection
echo "Test 3: SSE Stream Test (10 seconds)"
echo "-------------------------------------"
echo "Connecting to SSE stream for zone 1..."
echo "You should see 'connected' event and any price updates..."
echo ""
timeout 10 curl -N -H "Accept: text/event-stream" http://localhost:8081/api/v1/zones/1/stream
echo ""
echo ""

# Test 4: Test CORS
echo "Test 4: CORS Test"
echo "-----------------"
echo "Testing CORS from localhost:3000 origin..."
CORS=$(curl -s -I -X OPTIONS \
  -H "Origin: http://localhost:3000" \
  -H "Access-Control-Request-Method: GET" \
  -H "Access-Control-Request-Headers: Content-Type" \
  http://localhost:8081/api/v1/zones/1/stream 2>&1)

if echo "$CORS" | grep -q "Access-Control-Allow-Origin"; then
    echo "✓ CORS is configured"
    echo "$CORS" | grep "Access-Control"
else
    echo "✗ CORS might not be configured"
    echo "Headers received:"
    echo "$CORS"
fi
echo ""

# Test 5: Check active connections
echo "Test 5: Active SSE Connections"
echo "-------------------------------"
HEALTH=$(curl -s http://localhost:8081/api/v1/health)
CONNECTIONS=$(echo "$HEALTH" | jq -r '.active_sse_connections' 2>/dev/null)
echo "Active SSE connections: $CONNECTIONS"
echo ""

echo "=========================="
echo "✓ All tests complete!"
echo ""
echo "💡 Tips:"
echo "   - If CORS test failed, rebuild the pricing-api"
echo "   - If SSE stream shows nothing, check if Flink job is running"
echo "   - If no data after 15 seconds, check logs/flink-job.log"
echo "   - View frontend at: http://localhost:3000"

