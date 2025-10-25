#!/bin/bash
set -e

echo "🚀 Quick Start - Dynamic Pricing System"
echo "========================================"

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create logs directory
mkdir -p logs

# Step 1: Start Infrastructure
echo -e "\n${YELLOW}[1/5]${NC} Starting infrastructure (Kafka + PostgreSQL)..."
cd infra
docker compose up -d
cd "$PROJECT_ROOT"
echo -e "${GREEN}✓${NC} Infrastructure started"

# Wait for services
echo -e "\n${YELLOW}[2/5]${NC} Waiting for services to be ready..."
echo "   Waiting for PostgreSQL..."
sleep 5
until docker compose -f infra/docker-compose.yml exec -T postgres pg_isready -U pricing -d pricing > /dev/null 2>&1; do
    sleep 2
done
echo -e "${GREEN}✓${NC} PostgreSQL ready"

echo "   Waiting for Kafka (this may take 30-40 seconds)..."
sleep 10
until docker compose -f infra/docker-compose.yml exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list > /dev/null 2>&1; do
    sleep 3
    echo "   Still waiting for Kafka..."
done
echo -e "${GREEN}✓${NC} Kafka ready"

# Step 2: Create Topics
echo -e "\n${YELLOW}[3/5]${NC} Creating Kafka topics..."
cd infra
./reset-topics.sh
cd "$PROJECT_ROOT"

# Step 3: Build
echo -e "\n${YELLOW}[4/5]${NC} Building applications..."
./gradlew :flink-pricing-job:shadowJar :services:pricing-api:bootJar :services:event-generator:bootJar -q
echo -e "${GREEN}✓${NC} Build complete"

# Step 4: Start services
echo -e "\n${YELLOW}[5/5]${NC} Starting services..."

echo "   Starting Pricing API..."
./gradlew :services:pricing-api:bootRun > logs/pricing-api.log 2>&1 &
PRICING_API_PID=$!
echo "$PRICING_API_PID" > logs/pricing-api.pid
echo -e "   ${GREEN}✓${NC} Pricing API started (PID: $PRICING_API_PID)"

# Wait for API to be ready
sleep 8
echo "   Checking API health..."
until curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1; do
    sleep 2
    echo "   Waiting for Pricing API..."
done
echo -e "   ${GREEN}✓${NC} Pricing API is healthy"

echo "   Starting Flink Job..."
java --add-opens java.base/java.lang=ALL-UNNAMED \
     -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar > logs/flink-job.log 2>&1 &
FLINK_PID=$!
echo "$FLINK_PID" > logs/flink-job.pid
echo -e "   ${GREEN}✓${NC} Flink Job started (PID: $FLINK_PID)"

sleep 5

echo "   Starting Event Generator..."
DETERMINISTIC=true \
EXPERIMENT_SEED=12345 \
SCENARIO=normal \
./gradlew :services:event-generator:bootRun > logs/event-generator.log 2>&1 &
GENERATOR_PID=$!
echo "$GENERATOR_PID" > logs/event-generator.pid
echo -e "   ${GREEN}✓${NC} Event Generator started (PID: $GENERATOR_PID)"

sleep 3

echo "   Starting Frontend Dashboard..."
cd frontend
python3 server.py > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > ../logs/frontend.pid
cd "$PROJECT_ROOT"
echo -e "   ${GREEN}✓${NC} Frontend Dashboard started (PID: $FRONTEND_PID)"

# Summary
echo -e "\n${GREEN}===================================="
echo "🎉 System Started Successfully!"
echo "====================================${NC}"
echo ""
echo "📊 Access Points:"
echo "   - Frontend:      http://localhost:3000"
echo "   - Pricing API:   http://localhost:8081"
echo "   - Health Check:  http://localhost:8081/api/v1/health"
echo ""
echo "📝 View Logs:"
echo "   - tail -f logs/pricing-api.log"
echo "   - tail -f logs/flink-job.log"
echo "   - tail -f logs/event-generator.log"
echo ""
echo "🧪 Test SSE Stream:"
echo "   - curl -N http://localhost:8081/api/v1/zones/1/stream"
echo ""
echo "🛑 Stop all: ./stop-all.sh"
echo ""

