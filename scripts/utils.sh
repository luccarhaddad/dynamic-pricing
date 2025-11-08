#!/bin/bash
# utils.sh - Utility commands
#
# Usage:
#   ./scripts/utils.sh check-deps     - Check prerequisites
#   ./scripts/utils.sh port-check     - Check port conflicts
#   ./scripts/utils.sh kafka-topics   - List Kafka topics
#   ./scripts/utils.sh kafka-consume  - Consume from a Kafka topic

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Check dependencies
#######################################
check_deps() {
    echo -e "${BLUE}🔍 Checking Prerequisites${NC}"
    echo "=========================================="
    
    local all_good=true
    
    # Docker
    echo -en "${YELLOW}Docker:${NC} "
    if command -v docker &> /dev/null && docker info > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} installed and running"
    else
        echo -e "${RED}✗${NC} not running"
        all_good=false
    fi
    
    # Java
    echo -en "${YELLOW}Java:${NC} "
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | head -n 1 | awk -F '"' '{print $2}')
        echo -e "${GREEN}✓${NC} $JAVA_VERSION"
    else
        echo -e "${RED}✗${NC} not found"
        all_good=false
    fi
    
    # Gradle
    echo -en "${YELLOW}Gradle:${NC} "
    if [ -f "$PROJECT_ROOT/gradlew" ]; then
        echo -e "${GREEN}✓${NC} wrapper present"
    else
        echo -e "${RED}✗${NC} wrapper not found"
        all_good=false
    fi
    
    # Python
    echo -en "${YELLOW}Python 3:${NC} "
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version | awk '{print $2}')
        echo -e "${GREEN}✓${NC} $PYTHON_VERSION"
    else
        echo -e "${RED}✗${NC} not found"
        all_good=false
    fi
    
    # kubectl (optional for K8s)
    echo -en "${YELLOW}kubectl:${NC} "
    if command -v kubectl &> /dev/null; then
        KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | awk '{print $3}' || echo "unknown")
        echo -e "${GREEN}✓${NC} $KUBECTL_VERSION"
    else
        echo -e "${YELLOW}⚠${NC} not found (required for K8s only)"
    fi
    
    # Minikube (optional for K8s)
    echo -en "${YELLOW}minikube:${NC} "
    if command -v minikube &> /dev/null; then
        MINIKUBE_VERSION=$(minikube version --short 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓${NC} $MINIKUBE_VERSION"
    else
        echo -e "${YELLOW}⚠${NC} not found (optional for local K8s)"
    fi
    
    echo ""
    if [ "$all_good" = true ]; then
        echo -e "${GREEN}✅ All required dependencies installed${NC}"
    else
        echo -e "${RED}❌ Some required dependencies are missing${NC}"
        exit 1
    fi
}

#######################################
# Check port conflicts
#######################################
port_check() {
    echo -e "${BLUE}🔍 Checking Port Usage${NC}"
    echo "=========================================="
    
    local ports=(
        "8081:Pricing API"
        "8082:Event Generator"
        "3000:Frontend"
        "19092:Kafka (external)"
        "5432:PostgreSQL"
        "8080:Kafka UI"
    )
    
    local conflicts=false
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port service <<< "$port_info"
        
        echo -en "${YELLOW}Port $port ($service):${NC} "
        if lsof -i:$port > /dev/null 2>&1; then
            PID=$(lsof -ti:$port)
            PROCESS=$(ps -p $PID -o comm= 2>/dev/null || echo "unknown")
            echo -e "${RED}✗${NC} in use by $PROCESS (PID: $PID)"
            conflicts=true
        else
            echo -e "${GREEN}✓${NC} available"
        fi
    done
    
    echo ""
    if [ "$conflicts" = true ]; then
        echo -e "${YELLOW}⚠️  Port conflicts detected${NC}"
        echo ""
        echo "To kill processes on specific ports:"
        echo "  kill \$(lsof -ti:8081)  # Kill process on port 8081"
        echo ""
        echo "Or stop all services:"
        echo "  ./scripts/dev.sh stop"
        echo ""
    else
        echo -e "${GREEN}✅ All ports available${NC}"
    fi
}

#######################################
# List Kafka topics
#######################################
kafka_topics() {
    echo -e "${BLUE}📋 Kafka Topics${NC}"
    echo "=========================================="
    
    if ! docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" ps | grep -q kafka; then
        echo -e "${RED}✗ Kafka is not running${NC}"
        echo "Start infrastructure: ./scripts/dev.sh start"
        exit 1
    fi
    
    echo "Topics:"
    docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec -T kafka \
        /opt/kafka/bin/kafka-topics.sh \
        --bootstrap-server localhost:19092 \
        --list
    
    echo ""
    echo "Topic details:"
    for topic in ride-requests driver-heartbeats price-updates; do
        echo -e "\n${YELLOW}$topic:${NC}"
        docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec -T kafka \
            /opt/kafka/bin/kafka-topics.sh \
            --bootstrap-server localhost:19092 \
            --describe \
            --topic "$topic" 2>/dev/null || echo "  Topic not found"
    done
    echo ""
}

#######################################
# Detect environment and configure
#######################################
detect_env() {
    echo -e "${BLUE}🔍 Detecting Environment${NC}"
    echo "=========================================="
    
    local detected_host="host.docker.internal"
    local os_type=$(uname -s)
    local docker_runtime="unknown"
    
    # Detect OS
    echo -e "${YELLOW}Operating System:${NC} $os_type"
    
    # Detect Docker runtime
    if docker info 2>/dev/null | grep -q "OrbStack"; then
        docker_runtime="OrbStack"
    elif docker info 2>/dev/null | grep -q "Docker Desktop"; then
        docker_runtime="Docker Desktop"
    elif command -v podman &> /dev/null; then
        docker_runtime="Podman"
    else
        docker_runtime="Docker"
    fi
    echo -e "${YELLOW}Container Runtime:${NC} $docker_runtime"
    
    # Determine the right hostname
    case "$os_type" in
        Darwin)
            # macOS - host.docker.internal works for Docker Desktop and OrbStack
            detected_host="host.docker.internal"
            echo -e "${GREEN}✓${NC} Detected macOS - using host.docker.internal"
            ;;
        Linux)
            if [ "$docker_runtime" = "Podman" ]; then
                detected_host="host.containers.internal"
                echo -e "${GREEN}✓${NC} Detected Podman - using host.containers.internal"
            else
                # On Linux, get the Docker bridge IP
                detected_host=$(docker network inspect bridge | grep -m1 "Gateway" | awk '{print $2}' | tr -d '",')
                if [ -z "$detected_host" ]; then
                    detected_host="172.17.0.1"
                fi
                echo -e "${GREEN}✓${NC} Detected Linux Docker - using $detected_host"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            # Windows
            detected_host="host.docker.internal"
            echo -e "${GREEN}✓${NC} Detected Windows - using host.docker.internal"
            ;;
        *)
            echo -e "${YELLOW}⚠${NC} Unknown OS, defaulting to host.docker.internal"
            ;;
    esac
    
    # Create or update .env file
    local env_file="$PROJECT_ROOT/.env"
    echo ""
    echo -e "${YELLOW}Configuration:${NC}"
    echo "  KAFKA_EXTERNAL_HOST=$detected_host"
    
    if [ -f "$env_file" ]; then
        echo ""
        echo -e "${YELLOW}⚠  .env file already exists${NC}"
        read -p "Do you want to update it? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted. Current .env file unchanged."
            return 0
        fi
    fi
    
    # Write .env file
    cat > "$env_file" << EOF
# Dynamic Pricing System - Environment Configuration
# Auto-generated by: ./scripts/utils.sh detect-env
# Generated on: $(date)

# Kafka external host for cross-Docker-network communication
# This hostname is used by Kubernetes (Flink) to reach Kafka running in docker-compose
KAFKA_EXTERNAL_HOST=$detected_host

# Detected environment:
# OS: $os_type
# Runtime: $docker_runtime
EOF
    
    echo ""
    echo -e "${GREEN}✅ Created $env_file${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the .env file if needed: cat .env"
    echo "  2. Start the system: ./scripts/dev.sh start"
    echo ""
}

#######################################
# Consume from Kafka topic
#######################################
kafka_consume() {
    local topic=${1:-}
    
    if [ -z "$topic" ]; then
        echo "Usage: $0 kafka-consume <topic>"
        echo ""
        echo "Available topics:"
        echo "  • ride-requests"
        echo "  • driver-heartbeats"
        echo "  • price-updates"
        echo ""
        echo "Example:"
        echo "  $0 kafka-consume price-updates"
        exit 1
    fi
    
    echo -e "${BLUE}📨 Consuming from topic: $topic${NC} (Ctrl+C to exit)"
    echo "=========================================="
    
    if ! docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" ps | grep -q kafka; then
        echo -e "${RED}✗ Kafka is not running${NC}"
        echo "Start infrastructure: ./scripts/dev.sh start"
        exit 1
    fi
    
    docker compose -f "$PROJECT_ROOT/infra/docker-compose.yml" exec kafka \
        /opt/kafka/bin/kafka-console-consumer.sh \
        --bootstrap-server localhost:19092 \
        --topic "$topic" \
        --from-beginning \
        --max-messages 10 \
        --property print.timestamp=true \
        --property print.key=true \
        --property print.value=true
}

# Main
case "${1:-}" in
    check-deps)
        check_deps
        ;;
    port-check)
        port_check
        ;;
    detect-env)
        detect_env
        ;;
    kafka-topics)
        kafka_topics
        ;;
    kafka-consume)
        kafka_consume "${2:-}"
        ;;
    *)
        echo "Usage: $0 {check-deps|port-check|detect-env|kafka-topics|kafka-consume}"
        echo ""
        echo "Commands:"
        echo "  check-deps     - Check prerequisites (Docker, Java, Python, etc.)"
        echo "  port-check     - Check for port conflicts"
        echo "  detect-env     - Auto-detect environment and create .env file"
        echo "  kafka-topics   - List and describe Kafka topics"
        echo "  kafka-consume  - Consume messages from a Kafka topic"
        echo ""
        echo "Examples:"
        echo "  $0 check-deps                      # Check if everything is installed"
        echo "  $0 port-check                      # Check for port conflicts"
        echo "  $0 detect-env                      # Auto-configure for your environment"
        echo "  $0 kafka-topics                    # List Kafka topics"
        echo "  $0 kafka-consume price-updates     # Consume from topic"
        exit 1
        ;;
esac

