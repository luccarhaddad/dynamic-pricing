#!/bin/bash
set -e

echo "🚀 Dynamic Pricing System Startup Script"
echo "=========================================="

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if Docker is running
check_docker() {
    echo -e "\n${YELLOW}Checking Docker...${NC}"
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}✗ Docker is not running!${NC}"
        echo "Please start Docker Desktop and run this script again."
        exit 1
    fi
    echo -e "${GREEN}✓ Docker is running${NC}"
}

# Function to stop old processes
stop_old_processes() {
    echo -e "\n${YELLOW}Stopping old processes...${NC}"
    
    if [ -f logs/pricing-api.pid ]; then
        OLD_PID=$(cat logs/pricing-api.pid)
        if ps -p $OLD_PID > /dev/null 2>&1; then
            echo "Stopping pricing-api (PID: $OLD_PID)"
            kill $OLD_PID 2>/dev/null || true
            sleep 2
        fi
    fi
    
    if [ -f logs/flink-job.pid ]; then
        OLD_PID=$(cat logs/flink-job.pid)
        if ps -p $OLD_PID > /dev/null 2>&1; then
            echo "Stopping flink-job (PID: $OLD_PID)"
            kill $OLD_PID 2>/dev/null || true
            sleep 2
        fi
    fi
    
    if [ -f logs/event-generator.pid ]; then
        OLD_PID=$(cat logs/event-generator.pid)
        if ps -p $OLD_PID > /dev/null 2>&1; then
            echo "Stopping event-generator (PID: $OLD_PID)"
            kill $OLD_PID 2>/dev/null || true
            sleep 2
        fi
    fi
    
    if [ -f logs/frontend.pid ]; then
        OLD_PID=$(cat logs/frontend.pid)
        if ps -p $OLD_PID > /dev/null 2>&1; then
            echo "Stopping frontend (PID: $OLD_PID)"
            kill $OLD_PID 2>/dev/null || true
            sleep 1
        fi
    fi
    
    echo -e "${GREEN}✓ Old processes stopped${NC}"
}

# Check Docker first
check_docker

# Stop old processes
stop_old_processes

# Create logs directory
mkdir -p logs

# Step 1: Infrastructure
echo -e "\n${YELLOW}[1/6]${NC} Starting infrastructure (Kafka + PostgreSQL)..."
cd infra
docker compose up -d
cd "$PROJECT_ROOT"
echo -e "${GREEN}✓${NC} Infrastructure started"

# Wait for services
echo -e "\n${YELLOW}[2/6]${NC} Waiting for services to be ready..."
echo "   Waiting for PostgreSQL..."
sleep 5
until docker compose -f infra/docker-compose.yml exec -T postgres pg_isready -U pricing -d pricing > /dev/null 2>&1; do
    sleep 2
    echo "   Still waiting for PostgreSQL..."
done
echo -e "${GREEN}✓${NC} PostgreSQL ready"

echo "   Waiting for Kafka (this may take 30-40 seconds)..."
sleep 10
KAFKA_READY=0
for i in {1..20}; do
    if docker compose -f infra/docker-compose.yml exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list > /dev/null 2>&1; then
        KAFKA_READY=1
        break
    fi
    sleep 3
    echo "   Still waiting for Kafka... (attempt $i/20)"
done

if [ $KAFKA_READY -eq 0 ]; then
    echo -e "${RED}✗ Kafka failed to start${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Kafka ready"

# Step 2: Create Topics
echo -e "\n${YELLOW}[3/6]${NC} Creating Kafka topics..."
cd infra
./reset-topics.sh
cd "$PROJECT_ROOT"

# Step 3: Build
echo -e "\n${YELLOW}[4/6]${NC} Building applications..."
./gradlew :services:pricing-api:bootJar :services:event-generator:bootJar :flink-pricing-job:shadowJar -q
echo -e "${GREEN}✓${NC} Build complete"

# Step 4: Start Pricing API
echo -e "\n${YELLOW}[5/6]${NC} Starting Pricing API..."
./gradlew :services:pricing-api:bootRun > logs/pricing-api.log 2>&1 &
PRICING_API_PID=$!
echo "$PRICING_API_PID" > logs/pricing-api.pid
echo -e "${GREEN}✓${NC} Pricing API started (PID: $PRICING_API_PID)"

# Wait for API to be ready
echo "   Checking API health..."
sleep 10
API_READY=0
for i in {1..30}; do
    if curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1; then
        API_READY=1
        break
    fi
    sleep 2
    echo "   Waiting for Pricing API... (attempt $i/30)"
done

if [ $API_READY -eq 0 ]; then
    echo -e "${RED}✗ Pricing API failed to start. Check logs/pricing-api.log${NC}"
    tail -50 logs/pricing-api.log
    exit 1
fi
echo -e "${GREEN}✓${NC} Pricing API is healthy"

# Step 5: Start Flink Job
echo -e "\n${YELLOW}[6/6]${NC} Starting Flink Job..."
java --add-opens java.base/java.lang=ALL-UNNAMED \
     -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar > logs/flink-job.log 2>&1 &
FLINK_PID=$!
echo "$FLINK_PID" > logs/flink-job.pid
echo -e "${GREEN}✓${NC} Flink Job started (PID: $FLINK_PID)"

sleep 5

# Step 6: Start Event Generator
echo -e "\nStarting Event Generator..."
DETERMINISTIC=true \
EXPERIMENT_SEED=12345 \
SCENARIO=baseline \
FAILURE_RATE=0.0 \
NETWORK_DELAY_MS=0 \
BURST_MULTIPLIER=1.0 \
./gradlew :services:event-generator:bootRun > logs/event-generator.log 2>&1 &
GENERATOR_PID=$!
echo "$GENERATOR_PID" > logs/event-generator.pid
echo -e "${GREEN}✓${NC} Event Generator started (PID: $GENERATOR_PID)"

sleep 3

# Step 7: Start Frontend Dashboard
echo -e "\nStarting Frontend Dashboard..."
cd frontend
python3 server.py > ../logs/frontend.log 2>&1 &
FRONTEND_PID=$!
echo "$FRONTEND_PID" > ../logs/frontend.pid
cd "$PROJECT_ROOT"
echo -e "${GREEN}✓${NC} Frontend Dashboard started (PID: $FRONTEND_PID)"

# Summary
echo -e "\n${GREEN}===================================="
echo "🎉 System Started Successfully!"
echo "====================================${NC}"
echo ""
echo "📊 Access Points:"
echo "   - Frontend:      http://localhost:3000"
echo "   - Kafka UI:      http://localhost:8080"
echo "   - Pricing API:   http://localhost:8081"
echo "   - Event Gen:     http://localhost:8082"
echo "   - Health Check:  http://localhost:8081/api/v1/health"
echo ""
echo "🧪 Test SSE Connection:"
echo "   curl -N http://localhost:8081/api/v1/zones/1/stream"
echo ""
echo "📝 View Logs:"
echo "   - tail -f logs/pricing-api.log"
echo "   - tail -f logs/flink-job.log"
echo "   - tail -f logs/event-generator.log"
echo "   - tail -f logs/frontend.log"
echo ""
echo "🛑 Stop all: ./stop-all.sh"
echo ""

