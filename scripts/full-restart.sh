#!/bin/bash
set -e

echo "🔄 Full System Restart - Clearing All State"
echo "============================================="

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Step 1: Stop all services
echo -e "\n${YELLOW}[1/6]${NC} Stopping all services..."
./scripts/stop.sh
echo -e "${GREEN}✓${NC} Services stopped"

# Step 2: Wait a bit for cleanup
sleep 3

# Step 3: Remove Docker volumes to clear all state
echo -e "\n${YELLOW}[2/6]${NC} Removing Docker volumes to clear state..."
cd infra
if docker compose ps -q > /dev/null 2>&1; then
    docker compose down -v --remove-orphans 2>/dev/null || true
fi

# Remove volumes explicitly
echo "  Removing volumes: kafka_data, postgres_data, flink_checkpoints"
docker volume rm infra_kafka_data 2>/dev/null || true
docker volume rm infra_postgres_data 2>/dev/null || true
docker volume rm infra_flink_checkpoints 2>/dev/null || true
docker volume rm pricing-network 2>/dev/null || true

# Clean up any orphaned volumes
docker volume prune -f > /dev/null 2>&1 || true

cd "$PROJECT_ROOT"
echo -e "${GREEN}✓${NC} Docker volumes removed"

# Step 4: Clean up local checkpoint directories if they exist
echo -e "\n${YELLOW}[3/6]${NC} Cleaning local checkpoint directories..."
rm -rf checkpoints/ savepoints/ 2>/dev/null || true
echo -e "${GREEN}✓${NC} Local checkpoints cleared"

# Step 5: Clean up logs (optional - keep for debugging)
echo -e "\n${YELLOW}[4/6]${NC} Cleaning old log files..."
rm -f logs/*.log logs/*.pid 2>/dev/null || true
mkdir -p logs
echo -e "${GREEN}✓${NC} Logs cleared"

# Step 6: Wait a moment
sleep 2

# Step 7: Start system fresh
echo -e "\n${YELLOW}[5/6]${NC} Starting system with fresh state..."
./scripts/start.sh

echo -e "\n${GREEN}✅ Full restart complete!${NC}"
echo ""
echo "📋 Changes Applied:"
echo "  • ZoneMetricsAggregator.Accumulator implements Serializable"
echo "  • Using TumblingEventTimeWindows instead of TumblingProcessingTimeWindows"
echo ""
echo "💡 All state has been cleared:"
echo "  • Kafka offsets and data"
echo "  • PostgreSQL database"
echo "  • Flink checkpoints"
echo ""

