#!/bin/bash

echo "🔍 Verifying Dynamic Pricing System"
echo "===================================="
echo ""

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS=0
FAILED=0

# Helper function
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

# 3. Check Pricing API
echo ""
echo "3. Checking Pricing API..."
curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1
check "Pricing API responding"

HEALTH=$(curl -s http://localhost:8081/api/v1/health)
echo "$HEALTH" | grep -q "UP"
check "Pricing API status UP"

# 4. Check Event Generator
echo ""
echo "4. Checking Event Generator..."
curl -s http://localhost:8082/actuator/health > /dev/null 2>&1
check "Event Generator responding"

# 5. Test API endpoints
echo ""
echo "5. Testing API Endpoints..."
PRICE_RESPONSE=$(curl -s http://localhost:8081/api/v1/zones/1/price)
echo "$PRICE_RESPONSE" | grep -q "surgeMultiplier"
check "Get zone price endpoint"

# 6. Check for events in Kafka
echo ""
echo "6. Checking Kafka Event Flow..."

# Check ride-requests
RIDE_EVENTS=$(docker compose -f infra/docker-compose.yml exec -T kafka \
  /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:19092 --topic ride-requests --time -1 2>/dev/null | \
  awk -F ":" '{sum += $3} END {print sum}')

if [ "$RIDE_EVENTS" -gt 0 ]; then
    echo -e "${GREEN}✅${NC} Ride requests: $RIDE_EVENTS events"
    SUCCESS=$((SUCCESS+1))
else
    echo -e "${YELLOW}⚠️${NC}  Ride requests: No events yet (may need more time)"
fi

# Check driver-heartbeats
HEARTBEAT_EVENTS=$(docker compose -f infra/docker-compose.yml exec -T kafka \
  /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:19092 --topic driver-heartbeats --time -1 2>/dev/null | \
  awk -F ":" '{sum += $3} END {print sum}')

if [ "$HEARTBEAT_EVENTS" -gt 0 ]; then
    echo -e "${GREEN}✅${NC} Driver heartbeats: $HEARTBEAT_EVENTS events"
    SUCCESS=$((SUCCESS+1))
else
    echo -e "${YELLOW}⚠️${NC}  Driver heartbeats: No events yet (may need more time)"
fi

# Check price-updates
PRICE_EVENTS=$(docker compose -f infra/docker-compose.yml exec -T kafka \
  /opt/kafka/bin/kafka-run-class.sh kafka.tools.GetOffsetShell \
  --broker-list localhost:19092 --topic price-updates --time -1 2>/dev/null | \
  awk -F ":" '{sum += $3} END {print sum}')

if [ "$PRICE_EVENTS" -gt 0 ]; then
    echo -e "${GREEN}✅${NC} Price updates: $PRICE_EVENTS events"
    SUCCESS=$((SUCCESS+1))
else
    echo -e "${YELLOW}⚠️${NC}  Price updates: No events yet (may need more time)"
fi

# 7. Check process logs
echo ""
echo "7. Checking Process Status..."

if [ -f logs/pricing-api.pid ]; then
    PID=$(cat logs/pricing-api.pid)
    if ps -p $PID > /dev/null; then
        echo -e "${GREEN}✅${NC} Pricing API process running (PID: $PID)"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}❌${NC} Pricing API process not running"
        FAILED=$((FAILED+1))
    fi
else
    echo -e "${YELLOW}⚠️${NC}  Pricing API PID file not found"
fi

if [ -f logs/flink-job.pid ]; then
    PID=$(cat logs/flink-job.pid)
    if ps -p $PID > /dev/null; then
        echo -e "${GREEN}✅${NC} Flink Job process running (PID: $PID)"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}❌${NC} Flink Job process not running"
        FAILED=$((FAILED+1))
    fi
else
    echo -e "${YELLOW}⚠️${NC}  Flink Job PID file not found"
fi

if [ -f logs/event-generator.pid ]; then
    PID=$(cat logs/event-generator.pid)
    if ps -p $PID > /dev/null; then
        echo -e "${GREEN}✅${NC} Event Generator process running (PID: $PID)"
        SUCCESS=$((SUCCESS+1))
    else
        echo -e "${RED}❌${NC} Event Generator process not running"
        FAILED=$((FAILED+1))
    fi
else
    echo -e "${YELLOW}⚠️${NC}  Event Generator PID file not found"
fi

# 8. Database check
echo ""
echo "8. Checking Database..."
docker compose -f infra/docker-compose.yml exec -T postgres \
  psql -U pricing -d pricing -c "SELECT COUNT(*) FROM zone_price_snapshot;" > /dev/null 2>&1
check "Database schema initialized"

# Summary
echo ""
echo "===================================="
echo "Summary"
echo "===================================="
echo -e "${GREEN}Passed: $SUCCESS${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
fi
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 System is working correctly!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some checks failed. Review the output above.${NC}"
    echo ""
    echo "Troubleshooting tips:"
    echo "  - Check logs: tail -f logs/*.log"
    echo "  - View docker logs: docker compose -f infra/docker-compose.yml logs"
    echo "  - Restart: ./stop-all.sh && ./start-all.sh"
    exit 1
fi

