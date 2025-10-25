#!/bin/bash
set -e

echo "🚀 Dynamic Pricing System - Start"
echo "===================================="

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Create logs directory
mkdir -p logs

# Check Docker
echo -e "\n${YELLOW}[1/7]${NC} Checking Docker..."
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}✗ Docker is not running!${NC}"
    echo "Please start Docker Desktop and run this script again."
    exit 1
fi
echo -e "${GREEN}✓${NC} Docker is running"

# Stop old processes
echo -e "\n${YELLOW}[2/7]${NC} Stopping old processes..."
for pid_file in logs/*.pid; do
    if [ -f "$pid_file" ]; then
        OLD_PID=$(cat "$pid_file")
        if ps -p $OLD_PID > /dev/null 2>&1; then
            SERVICE_NAME=$(basename "$pid_file" .pid)
            echo "  Stopping $SERVICE_NAME (PID: $OLD_PID)"
            kill $OLD_PID 2>/dev/null || true
        fi
        rm "$pid_file"
    fi
done
echo -e "${GREEN}✓${NC} Old processes stopped"

# Start infrastructure
echo -e "\n${YELLOW}[3/7]${NC} Starting infrastructure (Kafka + PostgreSQL)..."
cd infra
docker compose up -d
cd "$PROJECT_ROOT"
echo -e "${GREEN}✓${NC} Infrastructure started"

# Wait for services
echo -e "\n${YELLOW}[4/7]${NC} Waiting for services to be ready..."
echo "  Waiting for PostgreSQL..."
sleep 5
until docker compose -f infra/docker-compose.yml exec -T postgres pg_isready -U pricing -d pricing > /dev/null 2>&1; do
    sleep 2
done
echo -e "${GREEN}✓${NC} PostgreSQL ready"

echo "  Waiting for Kafka (30-40 seconds)..."
sleep 10
until docker compose -f infra/docker-compose.yml exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list > /dev/null 2>&1; do
    sleep 3
    echo "    Still waiting..."
done
echo -e "${GREEN}✓${NC} Kafka ready"

# Create topics
echo -e "\n${YELLOW}[5/7]${NC} Creating Kafka topics..."
cd infra
./reset-topics.sh
cd "$PROJECT_ROOT"

# Build applications
echo -e "\n${YELLOW}[6/7]${NC} Building applications..."
./gradlew :services:pricing-api:bootJar :services:event-generator:bootJar :flink-pricing-job:shadowJar -q
echo -e "${GREEN}✓${NC} Build complete"

# Start services
echo -e "\n${YELLOW}[7/7]${NC} Starting services..."

# Pricing API
./gradlew :services:pricing-api:bootRun > logs/pricing-api.log 2>&1 &
echo $! > logs/pricing-api.pid
echo "  ✓ Pricing API started (PID $(cat logs/pricing-api.pid))"

sleep 3

# Flink Job
java --add-opens java.base/java.lang=ALL-UNNAMED \
     -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar > logs/flink-job.log 2>&1 &
FLINK_PID=$!
echo "$FLINK_PID" > logs/flink-job.pid
echo "  ✓ Flink Job started (PID $FLINK_PID)"

sleep 3

# Event Generator
./gradlew :services:event-generator:bootRun > logs/event-generator.log 2>&1 &
echo $! > logs/event-generator.pid
echo "  ✓ Event Generator started (PID $(cat logs/event-generator.pid))"

sleep 3

# Frontend
cd frontend
python3 server.py > ../logs/frontend.log 2>&1 &
echo $! > ../logs/frontend.pid
cd "$PROJECT_ROOT"
echo "  ✓ Frontend started (PID $(cat logs/frontend.pid))"

echo ""
echo -e "${GREEN}✅ System started successfully!${NC}"
echo ""
echo "📊 Services:"
echo "  • Pricing API:     http://localhost:8081/api/v1/health"
echo "  • Event Generator: http://localhost:8082/actuator/health"
echo "  • Frontend:        http://localhost:3000"
echo "  • Kafka UI:        http://localhost:8080"
echo ""
echo "📝 View Logs:"
echo "  • tail -f logs/pricing-api.log"
echo "  • tail -f logs/flink-job.log"
echo "  • tail -f logs/event-generator.log"
echo "  • tail -f logs/frontend.log"
echo ""
echo "🛑 Stop: ./scripts/stop.sh"
echo "🔍 Verify: ./scripts/verify.sh"
echo ""

