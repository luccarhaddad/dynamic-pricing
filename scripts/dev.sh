#!/bin/bash
# dev.sh - Local development operations
#
# Usage:
#   ./scripts/dev.sh start    - Start local development environment
#   ./scripts/dev.sh stop     - Stop all services
#   ./scripts/dev.sh restart  - Clean restart (removes all state)
#   ./scripts/dev.sh logs     - View logs
#   ./scripts/dev.sh status   - Check running services

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Start local environment
#######################################
dev_start() {
    echo -e "${BLUE}🚀 Starting Local Development Environment${NC}"
    echo "=========================================="
    
    # Check Docker
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}✗ Docker is not running${NC}"
        echo "Please start Docker Desktop and run this script again."
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Docker is running"
    
    # Stop old processes
    echo -e "\n${YELLOW}[1/5]${NC} Stopping old processes..."
    dev_stop_services
    
    # Start infrastructure
    echo -e "\n${YELLOW}[2/5]${NC} Starting infrastructure (Kafka + PostgreSQL)..."
    cd "$PROJECT_ROOT/infra"
    docker compose up -d
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓${NC} Infrastructure containers started"
    
    # Wait for services to be healthy and topics to be created
    echo -e "\n${YELLOW}[3/5]${NC} Waiting for services to be ready..."
    
    echo "  Waiting for PostgreSQL to be healthy..."
    until docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec -T postgres \
        pg_isready -U pricing -d pricing > /dev/null 2>&1; do
        sleep 2
        echo "    Still waiting for PostgreSQL..."
    done
    echo -e "${GREEN}✓${NC} PostgreSQL ready"
    
    echo "  Waiting for Kafka to be healthy..."
    until [ "$(docker inspect --format='{{.State.Health.Status}}' kafka 2>/dev/null)" = "healthy" ]; do
        sleep 3
        echo "    Still waiting for Kafka healthcheck..."
    done
    echo -e "${GREEN}✓${NC} Kafka ready"
    
    echo "  Waiting for Kafka topics to be created..."
    # Wait for kafka-init to complete (it creates the topics)
    until [ "$(docker inspect --format='{{.State.Status}}' kafka-init 2>/dev/null)" = "exited" ]; do
        sleep 2
        echo "    Still waiting for topic initialization..."
    done
    echo -e "${GREEN}✓${NC} Kafka topics created"
    
    # Build applications
    echo -e "\n${YELLOW}[4/5]${NC} Building Spring Boot applications..."
    "$PROJECT_ROOT/gradlew" -p "$PROJECT_ROOT" \
        :services:pricing-api:bootJar \
        :services:event-generator:bootJar -q
    echo -e "${GREEN}✓${NC} Build complete"
    
    # Start services
    echo -e "\n${YELLOW}[5/5]${NC} Starting services..."
    mkdir -p "$PROJECT_ROOT/logs"
    
    # Pricing API
    "$PROJECT_ROOT/gradlew" -p "$PROJECT_ROOT" :services:pricing-api:bootRun \
        > "$PROJECT_ROOT/logs/pricing-api.log" 2>&1 &
    echo $! > "$PROJECT_ROOT/logs/pricing-api.pid"
    echo "  ✓ Pricing API started (PID $(cat "$PROJECT_ROOT/logs/pricing-api.pid"))"
    sleep 3
    
    # Event Generator
    "$PROJECT_ROOT/gradlew" -p "$PROJECT_ROOT" :services:event-generator:bootRun \
        > "$PROJECT_ROOT/logs/event-generator.log" 2>&1 &
    echo $! > "$PROJECT_ROOT/logs/event-generator.pid"
    echo "  ✓ Event Generator started (PID $(cat "$PROJECT_ROOT/logs/event-generator.pid"))"
    sleep 3
    
    # Frontend
    cd "$PROJECT_ROOT/frontend"
    python3 server.py > "$PROJECT_ROOT/logs/frontend.log" 2>&1 &
    echo $! > "$PROJECT_ROOT/logs/frontend.pid"
    cd "$PROJECT_ROOT"
    echo "  ✓ Frontend started (PID $(cat "$PROJECT_ROOT/logs/frontend.pid"))"
    
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
    echo "  • All:       ./scripts/dev.sh logs"
    echo "  • API:       ./scripts/dev.sh logs api"
    echo "  • Generator: ./scripts/dev.sh logs generator"
    echo "  • Frontend:  ./scripts/dev.sh logs frontend"
    echo ""
    echo "🔍 Other Commands:"
    echo "  • Status: ./scripts/dev.sh status"
    echo "  • Stop:   ./scripts/dev.sh stop"
    echo ""
    echo "☸️  Deploy Flink to Kubernetes:"
    echo "  • Setup:  ./scripts/k8s.sh setup"
    echo "  • Deploy: ./scripts/k8s.sh deploy"
    echo ""
}

#######################################
# Stop services only (keep Docker)
#######################################
dev_stop_services() {
    # Kill Java processes by PID file
    for pid_file in "$PROJECT_ROOT"/logs/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            if kill -0 $PID 2>/dev/null; then
                SERVICE_NAME=$(basename "$pid_file" .pid)
                kill -TERM $PID 2>/dev/null || true
                sleep 1
                if kill -0 $PID 2>/dev/null; then
                    kill -KILL $PID 2>/dev/null || true
                fi
            fi
            rm "$pid_file"
        fi
    done
    
    # Kill by port (backup)
    for port in 8081 8082 3000; do
        PIDS=$(lsof -ti:$port 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
        fi
    done
    
    # Kill by process name (backup)
    pkill -f "flink-pricing-job" 2>/dev/null || true
    pkill -f "com.pricing.api.PricingApplication" 2>/dev/null || true
    pkill -f "com.pricing.generator.EventGeneratorApplication" 2>/dev/null || true
    pkill -f "frontend/server.py" 2>/dev/null || true
}

#######################################
# Stop everything
#######################################
dev_stop() {
    echo -e "${BLUE}🛑 Stopping Dynamic Pricing System${NC}"
    
    dev_stop_services
    
    # Stop Docker infrastructure
    if docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" ps > /dev/null 2>&1; then
        cd "$PROJECT_ROOT/infra"
        docker compose down
        cd "$PROJECT_ROOT"
        echo -e "${GREEN}✓${NC} Infrastructure stopped"
    fi
    
    echo ""
    echo -e "${GREEN}✓ System stopped successfully${NC}"
}

#######################################
# Full restart (clear state)
#######################################
dev_restart() {
    echo -e "${BLUE}🔄 Full System Restart - Clearing All State${NC}"
    echo "============================================="
    
    # Stop services
    echo -e "\n${YELLOW}[1/4]${NC} Stopping all services..."
    dev_stop_services
    echo -e "${GREEN}✓${NC} Services stopped"
    
    sleep 2
    
    # Remove Docker volumes to clear state
    echo -e "\n${YELLOW}[2/4]${NC} Removing Docker volumes to clear state..."
    cd "$PROJECT_ROOT/infra"
    if docker compose ps -q > /dev/null 2>&1; then
        docker compose down -v --remove-orphans 2>/dev/null || true
    fi
    
    # Remove volumes explicitly
    docker volume rm infra_kafka_data 2>/dev/null || true
    docker volume rm infra_postgres_data 2>/dev/null || true
    docker volume rm infra_flink_checkpoints 2>/dev/null || true
    docker volume prune -f > /dev/null 2>&1 || true
    
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓${NC} Docker volumes removed"
    
    # Clean up local files
    echo -e "\n${YELLOW}[3/4]${NC} Cleaning local files..."
    rm -rf "$PROJECT_ROOT/checkpoints" "$PROJECT_ROOT/savepoints" 2>/dev/null || true
    rm -f "$PROJECT_ROOT/logs"/*.log "$PROJECT_ROOT/logs"/*.pid 2>/dev/null || true
    mkdir -p "$PROJECT_ROOT/logs"
    echo -e "${GREEN}✓${NC} Local files cleaned"
    
    sleep 2
    
    # Start system fresh
    echo -e "\n${YELLOW}[4/4]${NC} Starting system with fresh state..."
    dev_start
    
    echo ""
    echo -e "${GREEN}✅ Full restart complete!${NC}"
    echo ""
    echo "💡 All state has been cleared:"
    echo "  • Kafka offsets and data"
    echo "  • PostgreSQL database"
    echo "  • Flink checkpoints"
    echo ""
}

#######################################
# View logs
#######################################
dev_logs() {
    local service=${1:-}
    
    case $service in
        api)
            echo -e "${BLUE}📝 Pricing API Logs${NC} (Ctrl+C to exit)"
            echo "========================================"
            tail -f "$PROJECT_ROOT/logs/pricing-api.log" 2>/dev/null || echo "No logs yet"
            ;;
        generator|gen)
            echo -e "${BLUE}📝 Event Generator Logs${NC} (Ctrl+C to exit)"
            echo "========================================"
            tail -f "$PROJECT_ROOT/logs/event-generator.log" 2>/dev/null || echo "No logs yet"
            ;;
        frontend)
            echo -e "${BLUE}📝 Frontend Logs${NC} (Ctrl+C to exit)"
            echo "========================================"
            tail -f "$PROJECT_ROOT/logs/frontend.log" 2>/dev/null || echo "No logs yet"
            ;;
        "")
            echo -e "${BLUE}📝 Recent Logs from All Services${NC}"
            echo "========================================"
            echo ""
            echo -e "${YELLOW}Pricing API (last 10 lines):${NC}"
            tail -n 10 "$PROJECT_ROOT/logs/pricing-api.log" 2>/dev/null || echo "  No logs yet"
            echo ""
            echo -e "${YELLOW}Event Generator (last 10 lines):${NC}"
            tail -n 10 "$PROJECT_ROOT/logs/event-generator.log" 2>/dev/null || echo "  No logs yet"
            echo ""
            echo -e "${YELLOW}Frontend (last 10 lines):${NC}"
            tail -n 10 "$PROJECT_ROOT/logs/frontend.log" 2>/dev/null || echo "  No logs yet"
            echo ""
            echo "💡 To follow a specific service:"
            echo "  ./scripts/dev.sh logs api"
            echo "  ./scripts/dev.sh logs generator"
            echo "  ./scripts/dev.sh logs frontend"
            echo ""
            echo "☸️  For Flink logs (runs in Kubernetes):"
            echo "  ./scripts/k8s.sh logs jobmanager"
            ;;
        *)
            echo -e "${RED}✗ Unknown service: $service${NC}"
            echo "Available services: api, generator, frontend"
            exit 1
            ;;
    esac
}

#######################################
# Check status
#######################################
dev_status() {
    echo -e "${BLUE}📊 Local Environment Status${NC}"
    echo "=========================================="
    
    # Docker containers
    echo -e "\n${YELLOW}Docker Containers:${NC}"
    if docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" ps 2>/dev/null | grep -q "Up"; then
        docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" ps
    else
        echo "  No containers running"
    fi
    
    # Application services
    echo -e "\n${YELLOW}Application Services:${NC}"
    local all_running=true
    for service in pricing-api event-generator frontend; do
        pid_file="$PROJECT_ROOT/logs/${service}.pid"
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            if kill -0 $PID 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $service (PID: $PID)"
            else
                echo -e "  ${RED}✗${NC} $service (not running)"
                all_running=false
            fi
        else
            echo -e "  ${RED}✗${NC} $service (not started)"
            all_running=false
        fi
    done
    
    echo -e "\n${YELLOW}Flink Job (Kubernetes):${NC}"
    echo -e "  ${BLUE}→${NC} Check status: ./scripts/k8s.sh status"
    
    # Port usage
    echo -e "\n${YELLOW}Port Status:${NC}"
    for port in 8081 8082 3000 19092 5432; do
        if lsof -i:$port > /dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} Port $port: in use"
        else
            echo -e "  ${RED}✗${NC} Port $port: available"
        fi
    done
    
    # Health checks
    echo -e "\n${YELLOW}Service Health:${NC}"
    
    # Pricing API
    if curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Pricing API: healthy"
    else
        echo -e "  ${RED}✗${NC} Pricing API: not responding"
    fi
    
    # Event Generator
    if curl -s http://localhost:8082/actuator/health > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Event Generator: healthy"
    else
        echo -e "  ${RED}✗${NC} Event Generator: not responding"
    fi
    
    # Frontend
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Frontend: healthy"
    else
        echo -e "  ${RED}✗${NC} Frontend: not responding"
    fi
    
    echo ""
    if [ "$all_running" = true ]; then
        echo -e "${GREEN}✅ All services running${NC}"
    else
        echo -e "${YELLOW}⚠️  Some services are not running${NC}"
        echo "Run './scripts/dev.sh start' to start all services"
    fi
}

# Main
case "${1:-}" in
    start)
        dev_start
        ;;
    stop)
        dev_stop
        ;;
    restart)
        dev_restart
        ;;
    logs)
        dev_logs "${2:-}"
        ;;
    status)
        dev_status
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|logs|status}"
        echo ""
        echo "Commands:"
        echo "  start    - Start local development environment"
        echo "  stop     - Stop all services"
        echo "  restart  - Clean restart (removes all state)"
        echo "  logs     - View logs (optionally specify: api, flink, generator, frontend)"
        echo "  status   - Check running services"
        echo ""
        echo "Examples:"
        echo "  $0 start              # Start everything"
        echo "  $0 logs flink         # Follow Flink logs"
        echo "  $0 status             # Check what's running"
        exit 1
        ;;
esac

