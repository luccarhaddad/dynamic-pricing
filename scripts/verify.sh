#!/bin/bash

echo "🔍 Verifying Dynamic Pricing System"
echo "===================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS=0
FAILED=0

check() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅${NC} $1"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}❌${NC} $1"
        FAILED=$((FAILED+1))
    fi
}

# 1. Check Docker containers
echo "1. Checking Docker Containers..."
docker compose -f infra/docker-compose.yml ps | grep -q "kafka.*Up"
check "Kafka container running"

docker compose -f infra/docker-compose.yml ps | grep -q "postgres.*healthy"
check "PostgreSQL container healthy"

# 2. Check Kafka topics
echo ""
echo "2. Checking Kafka Topics..."
TOPICS=$(docker compose -f infra/docker-compose.yml exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list 2>/dev/null)

echo "$TOPICS" | grep -q "ride-requests"
check "Topic: ride-requests"

echo "$TOPICS" | grep -q "driver-heartbeats"
check "Topic: driver-heartbeats"

echo "$TOPICS" | grep -q "price-updates"
check "Topic: price-updates"

# 3. Check Database
echo ""
echo "3. Checking Database..."
docker compose -f infra/docker-compose.yml exec -T postgres psql -U pricing -d pricing -c "\dt" > /dev/null 2>&1
check "Database accessible"

docker compose -f infra/docker-compose.yml exec -T postgres psql -U pricing -d pricing -c "SELECT COUNT(*) FROM zone_price_snapshot;" > /dev/null 2>&1
check "Table: zone_price_snapshot"

# 4. Check running processes
echo ""
echo "4. Checking Application Processes..."

if [ -f logs/pricing-api.pid ]; then
    PID=$(cat logs/pricing-api.pid)
    if ps -p $PID > /dev/null; then
        check "Pricing API running (PID: $PID)"
    else
        FAILED=$((FAILED+1))
        echo -e "${RED}❌${NC} Pricing API not running"
    fi
else
    FAILED=$((FAILED+1))
    echo -e "${RED}❌${NC} Pricing API not started"
fi

if [ -f logs/flink-job.pid ]; then
    PID=$(cat logs/flink-job.pid)
    if ps -p $PID > /dev/null; then
        check "Flink Job running (PID: $PID)"
    else
        FAILED=$((FAILED+1))
        echo -e "${RED}❌${NC} Flink Job not running"
    fi
else
    FAILED=$((FAILED+1))
    echo -e "${RED}❌${NC} Flink Job not started"
fi

if [ -f logs/event-generator.pid ]; then
    PID=$(cat logs/event-generator.pid)
    if ps -p $PID > /dev/null; then
        check "Event Generator running (PID: $PID)"
    else
        FAILED=$((FAILED+1))
        echo -e "${RED}❌${NC} Event Generator not running"
    fi
else
    FAILED=$((FAILED+1))
    echo -e "${RED}❌${NC} Event Generator not started"
fi

if [ -f logs/frontend.pid ]; then
    PID=$(cat logs/frontend.pid)
    if ps -p $PID > /dev/null; then
        check "Frontend running (PID: $PID)"
    else
        FAILED=$((FAILED+1))
        echo -e "${RED}❌${NC} Frontend not running"
    fi
else
    FAILED=$((FAILED+1))
    echo -e "${RED}❌${NC} Frontend not started"
fi

# 5. Check API endpoints
echo ""
echo "5. Checking API Endpoints..."

curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1
check "Pricing API health endpoint"

curl -s http://localhost:8082/actuator/health > /dev/null 2>&1
check "Event Generator health endpoint"

curl -s http://localhost:3000 > /dev/null 2>&1
check "Frontend accessible"

# Summary
echo ""
echo "===================================="
echo -e "Results: ${GREEN}$SUCCESS passed${NC}, ${RED}$FAILED failed${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "🌐 Access the system:"
    echo "  • Frontend:    http://localhost:3000"
    echo "  • Kafka UI:    http://localhost:8080"
    echo "  • Pricing API: http://localhost:8081/api/v1/health"
    exit 0
else
    echo -e "${RED}❌ Some checks failed. Check logs for details.${NC}"
    echo ""
    echo "📝 View logs:"
    echo "  • tail -f logs/pricing-api.log"
    echo "  • tail -f logs/flink-job.log"
    echo "  • tail -f logs/event-generator.log"
    exit 1
fi

