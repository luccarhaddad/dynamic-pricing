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
        echo "Please start Docker (Docker Desktop, OrbStack, or Docker Engine) and run this script again."
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Docker is running"
    
    # Clean up any stale PID files (services run in Docker now)
    echo -e "\n${YELLOW}[1/5]${NC} Cleaning up stale process files..."
    rm -f "$PROJECT_ROOT"/logs/*.pid 2>/dev/null || true
    
    # Start infrastructure
    echo -e "\n${YELLOW}[2/5]${NC} Starting infrastructure (Kafka + PostgreSQL)..."
    
    # Load .env file if it exists (for KAFKA_EXTERNAL_HOST)
    # If .env doesn't exist, auto-detect environment
    if [ -f "$PROJECT_ROOT/.env" ]; then
        set -a  # automatically export all variables
        source "$PROJECT_ROOT/.env"
        set +a
    else
        # Auto-detect environment and set KAFKA_EXTERNAL_HOST
        echo "  ${YELLOW}⚠${NC} No .env file found, auto-detecting environment..."
        source "$PROJECT_ROOT/scripts/utils.sh" 2>/dev/null || true
        
        # Detect Docker runtime and set appropriate hostname
        local detected_host="host.docker.internal"
        local os_type=$(uname -s)
        
        if docker info 2>/dev/null | grep -q "OrbStack"; then
            detected_host="host.docker.internal"  # OrbStack supports host.docker.internal
        elif docker info 2>/dev/null | grep -q "Docker Desktop"; then
            detected_host="host.docker.internal"  # Docker Desktop supports host.docker.internal
        elif [ "$os_type" = "Linux" ]; then
            # On Linux, try to get Docker bridge IP
            detected_host=$(docker network inspect bridge 2>/dev/null | grep -m1 "Gateway" | awk '{print $2}' | tr -d '",' || echo "172.17.0.1")
        fi
        
        export KAFKA_EXTERNAL_HOST="$detected_host"
        echo "  ${GREEN}✓${NC} Detected KAFKA_EXTERNAL_HOST=$detected_host"
        echo "  ${YELLOW}💡${NC} Run './scripts/utils.sh detect-env' to create .env file for persistence"
    fi
    
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
    
    # Build applications (needed for Docker images)
    echo -e "\n${YELLOW}[4/5]${NC} Building Spring Boot applications..."
    "$PROJECT_ROOT/gradlew" -p "$PROJECT_ROOT" \
        :services:pricing-api:bootJar \
        :services:event-generator:bootJar -q
    echo -e "${GREEN}✓${NC} Build complete"
    
    # Clean up old PID files (services now run in Docker)
    echo -e "\n${YELLOW}[5/5]${NC} Starting application services in Docker..."
    mkdir -p "$PROJECT_ROOT/logs"
    rm -f "$PROJECT_ROOT/logs"/*.pid 2>/dev/null || true
    
    # Services are now managed by docker-compose
    echo "  ✓ Services starting in Docker containers..."
    echo "  ✓ Pricing API (container)"
    echo "  ✓ Event Generator (container)"
    echo "  ✓ Frontend (container)"
    
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
# Stop Docker containers using docker compose
# All services run in Docker containers, so we stop them properly via docker compose
#######################################
dev_stop_services() {
    # Check Docker daemon is available
    if ! docker info > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} Docker daemon not available, skipping container stop"
        return 0
    fi
    
    # Stop Docker containers using docker compose
    cd "$PROJECT_ROOT/infra"
    if docker compose ps -q > /dev/null 2>&1; then
        echo "  Stopping Docker containers..."
        docker compose down --timeout 10 || {
            echo -e "${YELLOW}⚠${NC} Some containers may still be stopping"
        }
    else
        echo "  No containers running"
    fi
    cd "$PROJECT_ROOT"
    
    # Clean up old PID files (legacy from when services ran as processes)
    # Just remove the files, don't try to kill processes
    rm -f "$PROJECT_ROOT"/logs/*.pid 2>/dev/null || true
}

#######################################
# Stop everything
#######################################
dev_stop() {
    echo -e "${BLUE}🛑 Stopping Dynamic Pricing System${NC}"
    
    # Stop Docker containers (this handles all services)
    dev_stop_services
    
    echo ""
    echo -e "${GREEN}✓ System stopped successfully${NC}"
}

#######################################
# Full restart (clear state)
#######################################
dev_restart() {
    echo -e "${BLUE}🔄 Full System Restart - Clearing All State${NC}"
    echo "============================================="
    
    # Check Docker daemon is available
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}✗ Docker daemon is not running${NC}"
        echo "Please start Docker and run this script again."
        exit 1
    fi
    
    # Stop Docker containers first (with volume removal for clean restart)
    echo -e "\n${YELLOW}[1/4]${NC} Stopping Docker containers and removing volumes..."
    cd "$PROJECT_ROOT/infra"
    if docker compose ps -q > /dev/null 2>&1; then
        docker compose down -v --timeout 10 || {
            echo -e "${YELLOW}⚠${NC} Some containers may still be stopping"
        }
    fi
    cd "$PROJECT_ROOT"
    echo -e "${GREEN}✓${NC} Containers stopped and volumes removed"
    
    # Clean up local files
    echo -e "\n${YELLOW}[2/4]${NC} Cleaning local files..."
    rm -rf "$PROJECT_ROOT/checkpoints" "$PROJECT_ROOT/savepoints" 2>/dev/null || true
    rm -f "$PROJECT_ROOT/logs"/*.log "$PROJECT_ROOT/logs"/*.pid 2>/dev/null || true
    mkdir -p "$PROJECT_ROOT/logs"
    echo -e "${GREEN}✓${NC} Local files cleaned"
    
    sleep 2
    
    # Start system fresh
    echo -e "\n${YELLOW}[3/4]${NC} Starting system with fresh state..."
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
    
    # Application services (running in Docker)
    echo -e "\n${YELLOW}Application Services (Docker):${NC}"
    local all_running=true
    for service in pricing-api event-generator frontend; do
        if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            local status=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null)
            local health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' "$service" 2>/dev/null)
            if [ "$status" = "running" ]; then
                echo -e "  ${GREEN}✓${NC} $service ($health)"
            else
                echo -e "  ${RED}✗${NC} $service ($status)"
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

