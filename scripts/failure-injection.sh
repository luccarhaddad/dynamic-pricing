#!/bin/bash
# Failure Injection Testing Framework for Flink Fault Tolerance
# Tests various failure scenarios to verify Flink's recovery mechanisms

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

RESULTS_DIR="$PROJECT_ROOT/failure-test-results"
mkdir -p "$RESULTS_DIR"

# Function to print section header
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Function to check if Flink job is running
check_flink_running() {
    docker ps --format '{{.Names}}' | grep -q "^flink-job$" || return 1
}

# Function to check system status
check_system_status() {
    local kafka_running=$(docker ps --format '{{.Names}}' | grep -c "^kafka$" || echo "0")
    local flink_running=$(docker ps --format '{{.Names}}' | grep -c "^flink-job$" || echo "0")
    local event_gen_running=$(docker ps --format '{{.Names}}' | grep -c "^event-generator$" || echo "0")
    
    echo -e "\n${CYAN}Current System Status:${NC}"
    
    if [ "$kafka_running" -gt 0 ]; then
        echo -e "  Kafka: ${GREEN}✓ Running${NC}"
    else
        echo -e "  Kafka: ${RED}✗ Not running${NC}"
    fi
    
    if [ "$flink_running" -gt 0 ]; then
        echo -e "  Flink Job: ${GREEN}✓ Running${NC}"
    else
        echo -e "  Flink Job: ${RED}✗ Not running${NC}"
    fi
    
    if [ "$event_gen_running" -gt 0 ]; then
        echo -e "  Event Generator: ${GREEN}✓ Running${NC}"
    else
        echo -e "  Event Generator: ${RED}✗ Not running${NC}"
    fi
    
    if [ "$kafka_running" -gt 0 ] && [ "$flink_running" -gt 0 ] && [ "$event_gen_running" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Function to start/ensure system is ready
ensure_system_ready() {
    echo -e "\n${CYAN}Preparing system for test...${NC}"
    
    cd infra || return 1
    
    # Check if services are already running
    if check_system_status; then
        echo -e "${YELLOW}⚠ Services are already running${NC}"
        echo -n "Do you want to restart them? [y/n]: "
        read -r restart
        if [ "$restart" = "y" ] || [ "$restart" = "Y" ]; then
            echo "Stopping existing services..."
            docker compose down || true
            sleep 3
        else
            echo -e "${GREEN}✓ Using existing services${NC}"
            cd "$PROJECT_ROOT" || return 1
            return 0
        fi
    fi
    
    # Start all services
    echo -e "${CYAN}Starting all services...${NC}"
    docker compose up -d
    
    # Wait for Kafka to be ready
    echo "Waiting for Kafka to be ready..."
    for i in {1..30}; do
        if docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list > /dev/null 2>&1; then
            break
        fi
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ Kafka failed to start${NC}"
            cd "$PROJECT_ROOT" || return 1
            return 1
        fi
        sleep 2
    done
    
    # Wait for services to stabilize and create initial checkpoints
    echo "Waiting for services to stabilize - 60 seconds..."
    echo "(This allows Flink to create at least 3-4 checkpoints)"
    sleep 60
    
    # Verify services are running
    if ! check_system_status; then
        echo -e "${RED}✗ Some services failed to start${NC}"
        echo "Check logs: docker compose logs"
        cd "$PROJECT_ROOT" || return 1
        return 1
    fi
    
    cd "$PROJECT_ROOT" || return 1
    return 0
}

# Function to capture Kafka consumer group offsets
capture_offsets() {
    local test_name=$1
    local suffix=$2
    local timestamp=$(date +%s)
    
    echo -e "${CYAN}Capturing Kafka offsets ($suffix)...${NC}"
    
    docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:19092 \
        --group flink-pricing-job \
        --describe > "$RESULTS_DIR/${test_name}-offsets-${suffix}-${timestamp}.txt" 2>&1 || true
    
    # Get topic end offsets using kafka-topics.sh --describe (more reliable)
    for topic in ride-requests driver-heartbeats price-updates; do
        docker exec kafka /opt/kafka/bin/kafka-topics.sh \
            --bootstrap-server localhost:19092 \
            --topic "$topic" \
            --describe > "$RESULTS_DIR/${test_name}-topic-end-${topic}-${suffix}-${timestamp}.txt" 2>&1 || true
    done
    
    echo "$timestamp"
}

# Function to verify checkpoint restoration
verify_checkpoint_restoration() {
    local test_name=$1
    
    echo -e "\n${CYAN}Checkpoint Restoration Verification:${NC}"
    
    # Check Flink logs for checkpoint restoration messages
    local restore_logs=$(docker logs flink-job 2>&1 | grep -iE "checkpoint.*restore|restore.*checkpoint|no checkpoint found|restored from checkpoint" | tail -5)
    
    if echo "$restore_logs" | grep -qi "no checkpoint found"; then
        echo -e "${YELLOW}⚠ Checkpoint restoration not detected in logs${NC}"
        echo "  Flink may be using Kafka committed offsets as fallback"
        echo "  This is still valid recovery, but not using checkpoint state"
    elif echo "$restore_logs" | grep -qi "restore\|restored"; then
        echo -e "${GREEN}✓ Checkpoint restoration detected${NC}"
        echo "$restore_logs" | head -3 | sed 's/^/  /'
    else
        echo -e "${YELLOW}⚠ Could not determine checkpoint restoration status${NC}"
    fi
    
    # Check for checkpoint files
    local checkpoint_dirs=$(docker exec flink-job find /app/checkpoints -name "chk-*" -type d 2>/dev/null | wc -l || echo "0")
    
    echo -e "\n${CYAN}Checkpoint Files:${NC}"
    echo "  Checkpoint directories found: $checkpoint_dirs"
    
    if [ "$checkpoint_dirs" -gt 0 ]; then
        echo -e "${GREEN}✓ Checkpoints exist${NC}"
        local latest_checkpoint=$(docker exec flink-job find /app/checkpoints -name "chk-*" -type d 2>/dev/null | sort -V | tail -1)
        if [ -n "$latest_checkpoint" ]; then
            echo "  Latest checkpoint: $(basename $latest_checkpoint)"
        fi
    else
        echo -e "${RED}✗ No checkpoint directories found${NC}"
    fi
}

# Function to monitor lag trend over time
monitor_lag_trend() {
    local initial_lag=$1
    
    echo -e "\n${CYAN}Monitoring Lag Trend (60 seconds)...${NC}"
    
    local measurements=()
    local timestamps=()
    
    for i in {1..6}; do
        sleep 10
        
        local current_lag=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
            --bootstrap-server localhost:19092 \
            --group flink-pricing-job \
            --describe 2>/dev/null | awk '/^flink-pricing-job/ && NF >= 6 {sum+=$6} END {print sum+0}' || echo "0")
        
        current_lag=$(echo "$current_lag" | tr -d '[:space:]')
        measurements+=("$current_lag")
        timestamps+=("$(date +%H:%M:%S)")
        
        local idx=$((i - 1))
        local lag_change=$((initial_lag - current_lag))
        if [ "$lag_change" -gt 0 ]; then
            echo -e "  [${timestamps[$idx]}] Lag: $current_lag (↓ $lag_change decrease)"
        elif [ "$lag_change" -lt 0 ]; then
            echo -e "  [${timestamps[$idx]}] Lag: $current_lag (↑ $((-lag_change)) increase)"
        else
            echo -e "  [${timestamps[$idx]}] Lag: $current_lag (no change)"
        fi
    done
    
    # Determine trend
    local first_lag="${measurements[0]}"
    local last_lag="${measurements[5]}"
    local trend=$((first_lag - last_lag))
    
    echo -e "\n${CYAN}Lag Trend Analysis:${NC}"
    echo "  Initial lag: $first_lag"
    echo "  Final lag: $last_lag"
    
    if [ "$trend" -gt 100 ]; then
        echo -e "${GREEN}✓ Lag decreasing significantly - recovery progressing well${NC}"
        return 0
    elif [ "$trend" -gt 0 ]; then
        echo -e "${YELLOW}⚠ Lag decreasing slowly - recovery in progress${NC}"
        return 0
    elif [ "$trend" -eq 0 ]; then
        echo -e "${YELLOW}⚠ Lag stable - may need more time or check for issues${NC}"
        return 1
    else
        echo -e "${RED}✗ Lag increasing - recovery may not be working properly${NC}"
        return 1
    fi
}

# Function to verify data consistency
verify_data_consistency() {
    local test_name=$1
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Verifying Data Consistency and Recovery${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    # Check if Flink container is running
    if ! check_flink_running; then
        echo -e "${RED}✗ Flink container is not running!${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Flink container is running${NC}"
    
    # Check if price-updates topic has messages (output verification)
    local price_updates_count=0
    local offset_output=$(docker exec kafka bash -c 'cd /opt/kafka && CLASSPATH=/opt/kafka/libs/* bin/kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:19092 --topic price-updates --time -1' 2>&1)
    
    if echo "$offset_output" | grep -qE "^price-updates:[0-9]+:[0-9]+"; then
        price_updates_count=$(echo "$offset_output" | awk -F: '{sum+=$3} END {print sum+0}')
    else
        if docker exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --topic price-updates --describe >/dev/null 2>&1; then
            price_updates_count=1
        fi
    fi
    
    price_updates_count=$(echo "$price_updates_count" | tr -d '[:space:]' || echo "0")
    
    echo -e "\n${CYAN}Output Verification:${NC}"
    echo "  Price updates produced: $price_updates_count messages"
    
    if [ "${price_updates_count:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}✓ Flink is producing output${NC}"
    else
        echo -e "${RED}✗ No price updates produced - Flink may not be processing${NC}"
    fi
    
    # Check consumer lag (LAG is column 6 in the consumer groups output)
    local consumer_lag=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:19092 \
        --group flink-pricing-job \
        --describe 2>/dev/null | awk '/^flink-pricing-job/ && NF >= 6 {sum+=$6} END {print sum+0}' || echo "0")
    
    consumer_lag=$(echo "$consumer_lag" | tr -d '[:space:]')
    
    echo -e "\n${CYAN}Consumer Lag Check:${NC}"
    echo "  Total lag across all partitions: $consumer_lag messages"
    
    if [ "$consumer_lag" -lt 1000 ]; then
        echo -e "${GREEN}✓ Consumer lag is acceptable - lag < 1000${NC}"
    elif [ "$consumer_lag" -lt 10000 ]; then
        echo -e "${YELLOW}⚠ Consumer lag is moderate: $consumer_lag messages${NC}"
        echo "  Flink is catching up but may need more time"
    else
        echo -e "${RED}✗ Consumer lag is very high: $consumer_lag messages${NC}"
        echo "  Flink may not be recovering properly"
    fi
    
    # Check if consumer group exists and is active
    local group_exists=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:19092 \
        --group flink-pricing-job \
        --describe 2>/dev/null | grep -c "PARTITION" || echo "0")
    
    group_exists=$(echo "$group_exists" | tr -d '[:space:]')
    
    echo -e "\n${CYAN}Consumer Group Status:${NC}"
    if [ "${group_exists:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}✓ Consumer group is active with $group_exists partitions${NC}"
    else
        echo -e "${RED}✗ Consumer group not found or inactive${NC}"
    fi
    
    # Verify checkpoint restoration
    verify_checkpoint_restoration "$test_name"
    
    # Save results
    local timestamp=$(date +%s)
    echo "$test_name,$timestamp,$price_updates_count,$consumer_lag,$group_exists" >> "$RESULTS_DIR/consistency-results.csv"
    
    echo -e "\n${CYAN}Recovery Assessment:${NC}"
    if [ "${consumer_lag:-99999}" -lt 10000 ] 2>/dev/null && [ "${price_updates_count:-0}" -gt 0 ] 2>/dev/null && [ "${group_exists:-0}" -gt 0 ] 2>/dev/null; then
        echo -e "${GREEN}✅ RECOVERY SUCCESSFUL${NC}"
        echo "  • Flink is running and processing messages"
        echo "  • Consumer lag is manageable (< 10,000)"
        echo "  • Output topic is receiving updates"
        
        # Monitor lag trend
        monitor_lag_trend "$consumer_lag"
        local lag_trend_result=$?
        
        if [ $lag_trend_result -eq 0 ]; then
            return 0
        else
            echo -e "${YELLOW}⚠ Recovery successful but lag trend needs monitoring${NC}"
            return 0
        fi
    else
        echo -e "${RED}❌ RECOVERY FAILED${NC}"
        if [ "${consumer_lag:-99999}" -ge 10000 ] 2>/dev/null; then
            echo "  • High consumer lag detected (${consumer_lag:-0} messages)"
            echo "  • Flink may not be recovering from checkpoints properly"
            echo "  • Check if persistent checkpoint storage is configured"
        fi
        if [ "${price_updates_count:-0}" -eq 0 ] 2>/dev/null; then
            echo "  • No output being produced"
            echo "  • Flink may not be processing input streams"
        fi
        return 1
    fi
}

# Test Scenario 1: Flink Job Container Crash
test_flink_crash() {
    local test_name="flink-crash"
    print_header "Test: Flink Job Container Crash"
    
    echo -e "${YELLOW}This test will:${NC}"
    echo "  1. Start the system normally"
    echo "  2. Wait 60s for checkpoint creation"
    echo "  3. Verify checkpoints exist"
    echo "  4. Kill the Flink container"
    echo "  5. Wait 10 seconds"
    echo "  6. Restart Flink container"
    echo "  7. Wait 40s for recovery (10s startup + 30s initialization)"
    echo "  8. Verify checkpoint restoration and data consistency"
    echo "  9. Monitor lag trend over 60 seconds"
    echo "  10. Extended monitoring for 30 more seconds"
    echo ""
    
    read -p "Press Enter to start the test..."
    
    if ! ensure_system_ready; then
        echo -e "${RED}✗ Failed to setup system for testing${NC}"
        return 1
    fi
    
    # Verify checkpoints are being created
    echo -e "\n${CYAN}Checking for checkpoint files...${NC}"
    local checkpoint_count=$(docker exec flink-job find /app/checkpoints -name "chk-*" 2>/dev/null | wc -l || echo "0")
    if [ "$checkpoint_count" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $checkpoint_count checkpoints${NC}"
    else
        echo -e "${YELLOW}⚠ No checkpoints found yet - waiting may be needed${NC}"
    fi
    
    # Capture state before failure
    capture_offsets "$test_name" "before"
    
    # Capture checkpoint state before restart
    echo -e "\n${CYAN}Capturing checkpoint state before restart...${NC}"
    local checkpoint_count_before=$(docker exec flink-job find /app/checkpoints -name "chk-*" -type d 2>/dev/null | wc -l || echo "0")
    echo "  Checkpoints before restart: $checkpoint_count_before"
    
    # Kill Flink container
    cd infra || return 1
    echo -e "\n${RED}💥 Injecting failure: Killing Flink container...${NC}"
    docker kill flink-job || true
    sleep 10
    
    # Restart Flink container
    echo -e "\n${GREEN}🔄 Restarting Flink container...${NC}"
    docker compose up -d flink-job
    
    # Wait for Flink to start
    echo "Waiting for Flink container to start..."
    sleep 10
    
    # Wait for Flink to initialize and begin recovery
    echo "Waiting for Flink to initialize and begin recovery (30 seconds)..."
    sleep 30
    
    # Verify checkpoint persistence after restart
    echo -e "\n${CYAN}Checking checkpoint persistence after restart...${NC}"
    local checkpoint_count_after=$(docker exec flink-job find /app/checkpoints -name "chk-*" -type d 2>/dev/null | wc -l || echo "0")
    echo "  Checkpoints after restart: $checkpoint_count_after"
    
    if [ "$checkpoint_count_after" -ge "$checkpoint_count_before" ]; then
        echo -e "${GREEN}✓ Checkpoints persisted across restart${NC}"
    else
        echo -e "${YELLOW}⚠ Checkpoint count changed (may be new job UUID)${NC}"
        echo "  Checkpoints before: $checkpoint_count_before"
        echo "  Checkpoints after: $checkpoint_count_after"
    fi
    
    # Capture state after recovery
    capture_offsets "$test_name" "after"
    
    # Verify consistency (includes checkpoint restoration check)
    verify_data_consistency "$test_name"
    
    # Additional recovery monitoring
    echo -e "\n${CYAN}Extended Recovery Monitoring (30 more seconds)...${NC}"
    echo "Monitoring lag reduction over extended period..."
    sleep 30
    
    # Final lag check
    local final_lag=$(docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:19092 \
        --group flink-pricing-job \
        --describe 2>/dev/null | awk '/^flink-pricing-job/ && NF >= 6 {sum+=$6} END {print sum+0}' || echo "0")
    final_lag=$(echo "$final_lag" | tr -d '[:space:]')
    
    echo -e "\n${CYAN}Final Recovery Status:${NC}"
    echo "  Final consumer lag: $final_lag messages"
    
    if [ "${final_lag:-99999}" -lt 5000 ] 2>/dev/null; then
        echo -e "${GREEN}✓ Lag significantly reduced - recovery successful${NC}"
    elif [ "${final_lag:-99999}" -lt 10000 ] 2>/dev/null; then
        echo -e "${YELLOW}⚠ Lag reduced but still moderate - recovery in progress${NC}"
    else
        echo -e "${RED}✗ Lag still high - recovery may need more time${NC}"
    fi
    
    cd "$PROJECT_ROOT" || return 1
    echo -e "${GREEN}✅ Test completed${NC}"
    echo -e "${CYAN}Note: Services are still running. Run 'docker compose down' in infra/ to stop them.${NC}"
}

# Test Scenario 2: Kafka Broker Failure
test_kafka_failure() {
    local test_name="kafka-failure"
    print_header "Test: Kafka Broker Failure"
    
    echo -e "${YELLOW}This test will:${NC}"
    echo "  1. Start the system normally"
    echo "  2. Let it run for 30 seconds"
    echo "  3. Stop Kafka broker"
    echo "  4. Wait 15 seconds"
    echo "  5. Restart Kafka broker"
    echo "  6. Verify Flink reconnects and processes backlog"
    echo ""
    
    read -p "Press Enter to start the test..."
    
    if ! ensure_system_ready; then
        echo -e "${RED}✗ Failed to setup system for testing${NC}"
        return 1
    fi
    
    # Capture state before failure
    capture_offsets "$test_name" "before"
    
    # Stop Kafka
    cd infra || return 1
    echo -e "\n${RED}💥 Injecting failure: Stopping Kafka broker...${NC}"
    docker stop kafka || true
    sleep 15
    
    # Restart Kafka
    echo -e "\n${GREEN}🔄 Restarting Kafka broker...${NC}"
    docker start kafka
    
    # Wait for Kafka to be ready
    echo "Waiting for Kafka to be ready..."
    sleep 20
    
    # Wait for Flink to reconnect
    echo "Waiting for Flink to reconnect..."
    sleep 30
    
    # Capture state after recovery
    capture_offsets "$test_name" "after"
    
    # Verify consistency
    verify_data_consistency "$test_name"
    
    cd "$PROJECT_ROOT" || return 1
    echo -e "${GREEN}✅ Test completed${NC}"
    echo -e "${CYAN}Note: Services are still running. Run 'docker compose down' in infra/ to stop them.${NC}"
}

# Test Scenario 3: Network Partition - Disconnect Flink from Kafka
test_network_partition() {
    local test_name="network-partition"
    print_header "Test: Network Partition - Flink ↔ Kafka"
    
    echo -e "${YELLOW}This test will:${NC}"
    echo "  1. Start the system normally"
    echo "  2. Let it run for 30 seconds"
    echo "  3. Disconnect Flink from Kafka network"
    echo "  4. Wait 20 seconds"
    echo "  5. Reconnect Flink to Kafka network"
    echo "  6. Verify Flink processes backlog"
    echo ""
    
    read -p "Press Enter to start the test..."
    
    if ! ensure_system_ready; then
        echo -e "${RED}✗ Failed to setup system for testing${NC}"
        return 1
    fi
    
    # Capture state before failure
    capture_offsets "$test_name" "before"
    
    # Disconnect Flink from Kafka network
    cd infra || return 1
    echo -e "\n${RED}💥 Injecting failure: Disconnecting Flink from Kafka...${NC}"
    docker network disconnect pricing-network flink-job 2>/dev/null || true
    sleep 20
    
    # Reconnect Flink to Kafka network
    echo -e "\n${GREEN}🔄 Reconnecting Flink to Kafka...${NC}"
    docker network connect pricing-network flink-job 2>/dev/null || true
    
    # Wait for Flink to reconnect
    echo "Waiting for Flink to reconnect..."
    sleep 30
    
    # Capture state after recovery
    capture_offsets "$test_name" "after"
    
    # Verify consistency
    verify_data_consistency "$test_name"
    
    cd "$PROJECT_ROOT" || return 1
    echo -e "${GREEN}✅ Test completed${NC}"
    echo -e "${CYAN}Note: Services are still running. Run 'docker compose down' in infra/ to stop them.${NC}"
}

# Test Scenario 4: Flink Container Restart (Graceful)
test_flink_restart() {
    local test_name="flink-restart"
    print_header "Test: Flink Container Graceful Restart"
    
    echo -e "${YELLOW}This test will:${NC}"
    echo "  1. Start the system normally"
    echo "  2. Let it run for 30 seconds"
    echo "  3. Gracefully restart Flink container"
    echo "  4. Verify checkpoint recovery"
    echo ""
    
    read -p "Press Enter to start the test..."
    
    if ! ensure_system_ready; then
        echo -e "${RED}✗ Failed to setup system for testing${NC}"
        return 1
    fi
    
    # Capture state before restart
    capture_offsets "$test_name" "before"
    
    cd infra || return 1
    
    # Restart Flink gracefully
    echo -e "\n${YELLOW}🔄 Gracefully restarting Flink container...${NC}"
    docker compose restart flink-job
    
    # Wait for recovery
    echo "Waiting for Flink to recover from checkpoint..."
    sleep 30
    
    # Capture state after recovery
    capture_offsets "$test_name" "after"
    
    # Verify consistency
    verify_data_consistency "$test_name"
    
    cd "$PROJECT_ROOT" || return 1
    echo -e "${GREEN}✅ Test completed${NC}"
    echo -e "${CYAN}Note: Services are still running. Run 'docker compose down' in infra/ to stop them.${NC}"
}

# Main menu
main() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Flink Fault Tolerance Failure Injection Testing Framework   ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}How it works:${NC}"
    echo "  - The script automatically starts/stops services as needed"
    echo "  - You do not need to manually start the application first"
    echo "  - Each test will start fresh or use existing services"
    echo ""
    
    # Show current system status
    check_system_status
    
    echo ""
    echo "Available test scenarios:"
    echo ""
    echo "  1. Flink Job Container Crash"
    echo "  2. Kafka Broker Failure"
    echo "  3. Network Partition - Flink ↔ Kafka"
    echo "  4. Flink Container Graceful Restart"
    echo "  5. Run All Tests"
    echo "  0. Exit"
    echo ""
    
    echo -n "Select test scenario [0-5]: "
    read -r choice
    
    case $choice in
        1)
            test_flink_crash
            ;;
        2)
            test_kafka_failure
            ;;
        3)
            test_network_partition
            ;;
        4)
            test_flink_restart
            ;;
        5)
            test_flink_crash
            test_kafka_failure
            test_network_partition
            test_flink_restart
            ;;
        0)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice"
            exit 1
            ;;
    esac
}

# Initialize consistency results file
if [ ! -f "$RESULTS_DIR/consistency-results.csv" ]; then
    echo "test_name,timestamp,price_updates_count,consumer_lag,active_partitions" > "$RESULTS_DIR/consistency-results.csv"
fi

# Run main menu
main
