#!/bin/bash

# Experiment Runner for Dynamic Pricing System
# Runs deterministic experiments with different failure scenarios

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

RESULTS_DIR="experiment-results"
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}🧪 Dynamic Pricing Experiment Runner${NC}"
echo "======================================"
echo ""

# Function to cleanup any existing processes
cleanup_existing_processes() {
    echo "Cleaning up any existing processes..."
    
    # Kill by PID files
    for pid_file in logs/*.pid; do
        if [ -f "$pid_file" ]; then
            PID=$(cat "$pid_file")
            echo "Killing PID $PID from $pid_file"
            kill -9 $PID 2>/dev/null || true
            pkill -P $PID 2>/dev/null || true
            rm "$pid_file"
        fi
    done
    
    # Kill by port
    for port in 8081 8082 3000; do
        PIDS=$(lsof -ti:$port 2>/dev/null || true)
        if [ -n "$PIDS" ]; then
            echo "Killing processes on port $port"
            echo "$PIDS" | xargs kill -9 2>/dev/null || true
        fi
    done
    
    # Kill by process name
    pkill -f "flink-pricing-job" 2>/dev/null || true
    pkill -f "com.pricing.api.PricingApplication" 2>/dev/null || true
    pkill -f "com.pricing.generator.EventGeneratorApplication" 2>/dev/null || true
    pkill -f "frontend/server.py" 2>/dev/null || true
    
    sleep 2
}

run_experiment() {
    local scenario=$1
    local failure_rate=$2
    local network_delay=$3
    local burst_multiplier=$4
    local duration_minutes=$5
    local description=$6
    
    # Initialize PIDs
    local PRICING_API_PID=""
    local FLINK_PID=""
    local GENERATOR_PID=""
    local FRONTEND_PID=""
    
    echo -e "\n${YELLOW}Running Experiment: $description${NC}"
    echo "Scenario: $scenario"
    echo "Failure Rate: $failure_rate"
    echo "Network Delay: ${network_delay}ms"
    echo "Burst Multiplier: $burst_multiplier"
    echo "Duration: ${duration_minutes} minutes"
    echo ""
    
    # Cleanup any existing processes
    cleanup_existing_processes
    
    # Stop any running services
    ./scripts/stop.sh > /dev/null 2>&1 || true
    sleep 2
    
    # Ensure Docker containers are completely down
    cd infra
    docker compose down -v 2>/dev/null || true
    cd "$PROJECT_ROOT"
    sleep 2
    
    # Final cleanup before starting fresh
    cleanup_existing_processes
    
    # Start infrastructure
    echo "Starting infrastructure..."
    cd infra
    docker compose up -d
    cd "$PROJECT_ROOT"
    
    # Wait for services
    echo "Waiting for services to be ready..."
    sleep 30
    
    # Create topics
    cd infra
    ./reset-topics.sh
    cd "$PROJECT_ROOT"
    
    # Start Pricing API
    echo "Starting Pricing API..."
    ./gradlew :services:pricing-api:bootRun > logs/pricing-api-$scenario.log 2>&1 &
    PRICING_API_PID=$!
    echo "$PRICING_API_PID" > logs/pricing-api-$scenario.pid
    echo "Pricing API started (PID: $PRICING_API_PID)"
    
    # Wait for API to be ready
    sleep 10
    until curl -s http://localhost:8081/api/v1/health > /dev/null 2>&1; do
        sleep 2
    done
    
    # Start Flink Job
    echo "Starting Flink Job..."
    java --add-opens java.base/java.lang=ALL-UNNAMED \
         -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar > logs/flink-job-$scenario.log 2>&1 &
    FLINK_PID=$!
    echo "$FLINK_PID" > logs/flink-job-$scenario.pid
    echo "Flink Job started (PID: $FLINK_PID)"
    
    sleep 5
    
    # Start Event Generator with experiment parameters
    echo "Starting Event Generator with experiment parameters..."
    DETERMINISTIC=true \
    EXPERIMENT_SEED=12345 \
    SCENARIO=$scenario \
    FAILURE_RATE=$failure_rate \
    NETWORK_DELAY_MS=$network_delay \
    BURST_MULTIPLIER=$burst_multiplier \
    ./gradlew :services:event-generator:bootRun > logs/event-generator-$scenario.log 2>&1 &
    GENERATOR_PID=$!
    echo "$GENERATOR_PID" > logs/event-generator-$scenario.pid
    echo "Event Generator started (PID: $GENERATOR_PID)"
    
    sleep 3
    
    # Start Frontend Dashboard
    echo "Starting Frontend Dashboard..."
    cd frontend
    python3 server.py > ../logs/frontend-$scenario.log 2>&1 &
    FRONTEND_PID=$!
    echo "$FRONTEND_PID" > ../logs/frontend-$scenario.pid
    cd "$PROJECT_ROOT"
    echo "Frontend started (PID: $FRONTEND_PID)"
    
    echo "Experiment running for ${duration_minutes} minutes..."
    
    # Wait a bit for services to stabilize before collecting metrics
    echo "Waiting for services to stabilize..."
    sleep 10
    
    # Collect metrics during experiment
    local start_time=$(date +%s)
    local end_time=$((start_time + duration_minutes * 60))
    
    echo "Start time: $start_time, End time: $end_time"
    
    # Create metrics file
    local metrics_file="$RESULTS_DIR/metrics-$scenario.csv"
    echo "timestamp,zone_id,surge_multiplier,demand,supply,ratio" > "$metrics_file"
    
    # Collect metrics every 5 seconds
    local iteration=0
    while [ $(date +%s) -lt $end_time ]; do
        iteration=$((iteration + 1))
        echo "Collection iteration $iteration..."
        for zone in {1..16}; do
            local response=$(curl -s "http://localhost:8081/api/v1/zones/$zone/price" 2>/dev/null || echo '{"surge_multiplier":0,"demand":0,"supply":0,"ratio":0}')
            local timestamp=$(date +%s)
            local surge=$(echo "$response" | grep -o '"surge_multiplier":[0-9.]*' | cut -d: -f2 || echo "0")
            local demand=$(echo "$response" | grep -o '"demand":[0-9]*' | cut -d: -f2 || echo "0")
            local supply=$(echo "$response" | grep -o '"supply":[0-9]*' | cut -d: -f2 || echo "0")
            local ratio=$(echo "$response" | grep -o '"ratio":[0-9.]*' | cut -d: -f2 || echo "0")
            echo "$timestamp,$zone,$surge,$demand,$supply,$ratio" >> "$metrics_file"
        done
        sleep 5
    done
    
    # Stop services aggressively
    echo "Stopping services..."
    
    # Function to kill process and children
    kill_process_complete() {
        local pid=$1
        local name=$2
        if [ -n "$pid" ] && kill -0 $pid 2>/dev/null; then
            kill -TERM $pid 2>/dev/null || true
            sleep 1
            if kill -0 $pid 2>/dev/null; then
                kill -KILL $pid 2>/dev/null || true
            fi
            pkill -P $pid 2>/dev/null || true
            echo "  ✓ $name stopped"
        fi
    }
    
    kill_process_complete "$PRICING_API_PID" "Pricing API"
    kill_process_complete "$FLINK_PID" "Flink Job"
    kill_process_complete "$GENERATOR_PID" "Event Generator"
    kill_process_complete "$FRONTEND_PID" "Frontend"
    
    # Kill any remaining processes on our ports
    for port in 8081 8082 3000; do
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
    done
    
    # Kill any Java processes related to our services
    pkill -f "flink-pricing-job" 2>/dev/null || true
    pkill -f "com.pricing.api.PricingApplication" 2>/dev/null || true
    pkill -f "com.pricing.generator.EventGeneratorApplication" 2>/dev/null || true
    pkill -f "frontend/server.py" 2>/dev/null || true
    
    sleep 2
    
    # Stop infrastructure
    cd infra
    docker compose down -v 2>/dev/null || true
    cd "$PROJECT_ROOT"
    
    # Clean up any stray containers
    docker ps -a | grep -E "kafka|postgres|kafka-ui" | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Experiment '$scenario' completed${NC}"
    echo "Results saved to: $metrics_file"
    echo ""
}

# Function to analyze results
analyze_results() {
    echo -e "\n${BLUE}📊 Analyzing Results${NC}"
    echo "=================="
    
    local summary_file="$RESULTS_DIR/experiment-summary.csv"
    echo "scenario,failure_rate,network_delay,burst_multiplier,avg_surge,min_surge,max_surge,total_events" > "$summary_file"
    
    for metrics_file in "$RESULTS_DIR"/metrics-*.csv; do
        if [ -f "$metrics_file" ]; then
            local scenario=$(basename "$metrics_file" .csv | sed 's/metrics-//')
            local failure_rate=$(grep "FAILURE_RATE=" logs/event-generator-$scenario.log | head -1 | sed 's/.*FAILURE_RATE=//' | cut -d' ' -f1 || echo "0")
            local network_delay=$(grep "NETWORK_DELAY_MS=" logs/event-generator-$scenario.log | head -1 | sed 's/.*NETWORK_DELAY_MS=//' | cut -d' ' -f1 || echo "0")
            local burst_multiplier=$(grep "BURST_MULTIPLIER=" logs/event-generator-$scenario.log | head -1 | sed 's/.*BURST_MULTIPLIER=//' | cut -d' ' -f1 || echo "1")
            
            # Calculate statistics (skip header)
            local avg_surge=$(tail -n +2 "$metrics_file" | awk -F, '{sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
            local min_surge=$(tail -n +2 "$metrics_file" | awk -F, '{if(min=="" || $3<min) min=$3} END {print min+0}')
            local max_surge=$(tail -n +2 "$metrics_file" | awk -F, '{if(max=="" || $3>max) max=$3} END {print max+0}')
            local total_events=$(tail -n +2 "$metrics_file" | wc -l)
            
            echo "$scenario,$failure_rate,$network_delay,$burst_multiplier,$avg_surge,$min_surge,$max_surge,$total_events" >> "$summary_file"
            
            echo "Scenario: $scenario"
            echo "  Average Surge: $avg_surge"
            echo "  Min Surge: $min_surge"
            echo "  Max Surge: $max_surge"
            echo "  Total Events: $total_events"
            echo ""
        fi
    done
    
    echo -e "${GREEN}✅ Analysis complete${NC}"
    echo "Summary saved to: $summary_file"
}

# Main experiment execution
echo "Starting experiment..."

# Experiment: Baseline (no failures, deterministic mode)
run_experiment "baseline" "0.0" "0" "1.0" "2" "Baseline - No Failures"

# Analyze results
analyze_results

# Final cleanup - ensure everything is stopped
echo -e "\n${YELLOW}Final cleanup...${NC}"
cleanup_existing_processes

# Stop Docker one more time
cd infra
docker compose down -v 2>/dev/null || true
cd "$PROJECT_ROOT"

# Clean up any stray containers
docker ps -a | grep -E "kafka|postgres|kafka-ui" | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true

# Verify ports are free
echo -e "\n${BLUE}Verifying ports are free...${NC}"
for port in 8081 8082 3000; do
    if lsof -ti:$port > /dev/null 2>&1; then
        echo "⚠️  WARNING: Port $port is still in use!"
        lsof -ti:$port | xargs kill -9 2>/dev/null || true
    else
        echo "✓ Port $port is free"
    fi
done

echo -e "\n${GREEN}🎉 All experiments completed!${NC}"
echo "Results directory: $RESULTS_DIR"
echo ""
echo "To view results:"
echo "  - Individual metrics: ls $RESULTS_DIR/metrics-*.csv"
echo "  - Summary: cat $RESULTS_DIR/experiment-summary.csv"
echo ""
echo "To visualize results:"
echo "  - Use Excel/Google Sheets to import CSV files"
echo "  - Or use Python/R for statistical analysis"
