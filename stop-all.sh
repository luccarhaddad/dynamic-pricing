#!/bin/bash

echo "🛑 Stopping Dynamic Pricing System..."

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Function to kill process and its children aggressively
kill_process() {
    local pid=$1
    local name=$2
    
    if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
        # Kill main process
        kill -TERM $pid 2>/dev/null || true
        sleep 1
        
        # Force kill if still running
        if kill -0 $pid 2>/dev/null; then
            kill -KILL $pid 2>/dev/null || true
        fi
        
        # Kill all child processes
        pkill -P $pid 2>/dev/null || true
        
        echo "✓ $name stopped (PID: $pid)"
    fi
}

# Kill all processes by PID files
for pid_file in logs/*.pid; do
    if [ -f "$pid_file" ]; then
        PID=$(cat "$pid_file")
        SERVICE_NAME=$(basename "$pid_file" .pid)
        kill_process $PID "$SERVICE_NAME"
        rm "$pid_file"
    fi
done

# Kill processes on specific ports
echo "Checking for processes on ports 8081, 8082, 3000..."
for port in 8081 8082 3000; do
    PIDS=$(lsof -ti:$port 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        echo "Killing processes on port $port: $PIDS"
        echo "$PIDS" | xargs kill -9 2>/dev/null || true
    fi
done

# Kill any remaining Java processes related to our services
echo "Killing any remaining service processes..."
pkill -f "flink-pricing-job" 2>/dev/null || true
pkill -f "com.pricing.api.PricingApplication" 2>/dev/null || true
pkill -f "com.pricing.generator.EventGeneratorApplication" 2>/dev/null || true
pkill -f "frontend/server.py" 2>/dev/null || true

# Wait a bit for processes to die
sleep 2

# Stop Docker if running
if docker compose -f infra/docker-compose.yml ps > /dev/null 2>&1; then
    cd infra
    docker compose down -v
    cd "$PROJECT_ROOT"
    echo "✓ Infrastructure stopped"
else
    echo "✓ No Docker containers running"
fi

# Clean up any stray containers
docker ps -a | grep -E "kafka|postgres|kafka-ui" | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true

echo ""
echo "🎉 System stopped successfully"

