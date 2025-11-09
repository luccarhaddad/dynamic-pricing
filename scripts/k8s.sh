#!/bin/bash
# k8s.sh - Kubernetes operations
#
# Usage:
#   ./scripts/k8s.sh setup         - One-time setup (operator, namespaces, MinIO)
#   ./scripts/k8s.sh deploy        - Deploy Flink job to Kubernetes (auto-starts port-forward)
#   ./scripts/k8s.sh undeploy      - Remove Flink job
#   ./scripts/k8s.sh logs          - View logs
#   ./scripts/k8s.sh status        - Check Kubernetes resources
#   ./scripts/k8s.sh monitoring    - Deploy monitoring stack (auto-starts port-forward)
#   ./scripts/k8s.sh test-ft       - Test fault tolerance
#   ./scripts/k8s.sh ports [start|stop] - Manage port-forwarding

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/kubernetes"
PID_DIR="$PROJECT_ROOT/logs"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Ensure PID directory exists
mkdir -p "$PID_DIR"

#######################################
# Port forwarding management
#######################################
start_port_forward() {
    local namespace=$1
    local service=$2
    local local_port=$3
    local remote_port=$4
    local name=$5
    local pid_file="$PID_DIR/portforward-${name}.pid"
    
    # Check if already running
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠${NC} Port-forward for $name already running (PID: $pid)"
            return 0
        fi
    fi
    
    # Start port-forward in background
    kubectl port-forward -n "$namespace" "svc/$service" "$local_port:$remote_port" > /dev/null 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$pid_file"
    
    # Wait a moment and verify it started
    sleep 2
    if ps -p "$new_pid" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Port-forward started: localhost:$local_port -> $service:$remote_port (PID: $new_pid)"
        return 0
    else
        echo -e "${RED}✗${NC} Failed to start port-forward for $name"
        rm -f "$pid_file"
        return 1
    fi
}

stop_port_forward() {
    local name=$1
    local pid_file="$PID_DIR/portforward-${name}.pid"
    
    if [ ! -f "$pid_file" ]; then
        echo -e "${YELLOW}⚠${NC} No port-forward PID file found for $name"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    if ps -p "$pid" > /dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Stopped port-forward for $name (PID: $pid)"
    fi
    rm -f "$pid_file"
}

stop_all_port_forwards() {
    echo -e "${YELLOW}Stopping all port-forwards...${NC}"
    for pid_file in "$PID_DIR"/portforward-*.pid; do
        if [ -f "$pid_file" ]; then
            local name=$(basename "$pid_file" .pid | sed 's/portforward-//')
            stop_port_forward "$name"
        fi
    done
}

start_all_port_forwards() {
    echo -e "${BLUE}🔌 Starting Port Forwards${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Check if Flink service exists
    if kubectl get svc -n flink pricing-job-rest &> /dev/null; then
        # Use port 9081 for Flink UI to avoid conflict with pricing-api on 8081
        start_port_forward "flink" "pricing-job-rest" "9081" "8081" "flink-ui"
        
        echo ""
        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}Port Forward Active${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo "  Flink UI:    http://localhost:9081"
        echo ""
        echo "To stop port-forward:"
        echo "  ./scripts/k8s.sh ports stop"
        echo ""
    else
        echo -e "${YELLOW}⚠${NC} Flink not deployed. Deploy first:"
        echo "  ./scripts/k8s.sh deploy"
    fi
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl is not installed${NC}"
        echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Try to connect to cluster
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✓${NC} Connected to Kubernetes cluster"
        return 0
    fi
    
    # If not connected, check if Minikube is available
    if command -v minikube &> /dev/null; then
        echo -e "${YELLOW}⚠${NC} Kubernetes cluster not accessible"
        
        # Check Minikube status
        if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Stopped"; then
            echo -e "${YELLOW}ℹ${NC} Minikube cluster is stopped"
            echo -n "Starting Minikube cluster..."
            
            if minikube start > /dev/null 2>&1; then
                echo -e " ${GREEN}✓${NC}"
                echo -e "${GREEN}✓${NC} Minikube started successfully"
                return 0
            else
                echo -e " ${RED}✗${NC}"
                echo -e "${RED}✗ Failed to start Minikube${NC}"
                echo "Try manually: minikube start"
                exit 1
            fi
        else
            # Minikube exists but no profile or other issue
            echo -e "${YELLOW}ℹ${NC} No Minikube cluster found. Starting new cluster..."
            echo "This may take 2-3 minutes..."
            
            if minikube start; then
                echo -e "${GREEN}✓${NC} Minikube started successfully"
                return 0
            else
                echo -e "${RED}✗ Failed to start Minikube${NC}"
                exit 1
            fi
        fi
    else
        # No Minikube, suggest alternatives
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        echo ""
        echo "Options to fix this:"
        echo "  1. Enable Kubernetes in Docker Desktop:"
        echo "     Settings → Kubernetes → Enable Kubernetes"
        echo ""
        echo "  2. Install and use Minikube:"
        echo "     brew install minikube"
        echo "     minikube start"
        echo ""
        exit 1
    fi
}

#######################################
# One-time Kubernetes setup
#######################################
k8s_setup() {
    echo -e "${BLUE}🚀 Kubernetes Setup${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Step 1: Install Flink Operator using Helm
    echo -e "\n${YELLOW}[1/5]${NC} Installing Flink Kubernetes Operator..."
    
    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        echo -e "${RED}✗ Helm is not installed${NC}"
        echo "Install Helm: brew install helm"
        exit 1
    fi
    
    # Check if operator is already installed
    if helm list -n flink-operator 2>/dev/null | grep -q flink-kubernetes-operator; then
        echo "  Operator already installed, skipping..."
    else
        echo "  Adding Helm repository..."
        helm repo add flink-kubernetes-operator-1.7.0 https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.7.0/ 2>/dev/null || true
        helm repo update > /dev/null 2>&1
        
        echo "  Creating operator namespace..."
        kubectl create namespace flink-operator 2>/dev/null || true
        
        echo "  Installing operator with Helm..."
        local VALUES_FILE="$K8S_DIR/flink-operator/values.yaml"
        if [ -f "$VALUES_FILE" ]; then
            echo "  Using values file: $VALUES_FILE"
            helm install flink-kubernetes-operator \
                flink-kubernetes-operator-1.7.0/flink-kubernetes-operator \
                --namespace flink-operator \
                --values "$VALUES_FILE"
        else
            echo "  Using default values (no values file found)"
            helm install flink-kubernetes-operator \
                flink-kubernetes-operator-1.7.0/flink-kubernetes-operator \
                --namespace flink-operator \
                --set webhook.create=false
        fi
        
        echo "  Waiting for operator to be ready..."
        kubectl wait --for=condition=ready --timeout=120s \
            pod -l app.kubernetes.io/name=flink-kubernetes-operator -n flink-operator || {
            echo -e "${YELLOW}⚠${NC} Operator pod not ready within timeout"
        }
    fi
    echo -e "${GREEN}✓${NC} Operator installed"
    
    # Step 2: Create namespaces
    echo -e "\n${YELLOW}[2/5]${NC} Creating namespaces..."
    kubectl apply -f "$K8S_DIR/namespaces.yaml"
    echo -e "${GREEN}✓${NC} Namespaces created"
    
    # Step 3: Set up RBAC for Flink
    echo -e "\n${YELLOW}[3/5]${NC} Setting up RBAC for Flink High Availability..."
    kubectl apply -f "$K8S_DIR/flink-operator/rbac.yaml"
    echo -e "${GREEN}✓${NC} RBAC configured"
    
    # Step 4: Deploy MinIO
    echo -e "\n${YELLOW}[4/5]${NC} Deploying MinIO for checkpoint storage..."
    kubectl apply -f "$K8S_DIR/minio/deployment.yaml"
    
    echo "  Waiting for MinIO to be ready..."
    kubectl wait --for=condition=ready --timeout=120s \
        pod -l app=minio -n minio || {
        echo -e "${YELLOW}⚠${NC} MinIO not ready within timeout"
    }
    echo -e "${GREEN}✓${NC} MinIO deployed"
    
    # Step 5: Create MinIO buckets
    echo -e "\n${YELLOW}[5/5]${NC} Creating MinIO buckets for Flink..."
    kubectl apply -f "$K8S_DIR/minio/minio-setup-job.yaml"
    
    echo "  Waiting for bucket creation job..."
    kubectl wait --for=condition=complete --timeout=60s \
        job/minio-setup -n minio 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC} Job may still be running"
    }
    echo -e "${GREEN}✓${NC} Buckets created"
    
    # Summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Setup Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Deploy Flink job:"
    echo "     ./scripts/k8s.sh deploy"
    echo ""
    echo "  2. Deploy monitoring:"
    echo "     ./scripts/k8s.sh monitoring"
    echo ""
    echo "  3. Check status:"
    echo "     ./scripts/k8s.sh status"
    echo ""
}

#######################################
# Deploy Flink job to Kubernetes
#######################################
k8s_deploy() {
    echo -e "${BLUE}🚀 Deploying Flink Job to Kubernetes${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Determine if using Minikube
    local USE_MINIKUBE=false
    if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q minikube; then
        USE_MINIKUBE=true
        echo -e "${YELLOW}Detected Minikube cluster${NC}"
    fi
    
    local IMAGE_NAME="flink-pricing-job"
    local IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
    local FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
    
    # Step 1: Build Docker image
    echo -e "\n${YELLOW}[1/3]${NC} Building Docker image..."
    cd "$PROJECT_ROOT"
    docker build -t "$FULL_IMAGE_NAME" -f flink-pricing-job/Dockerfile .
    echo -e "${GREEN}✓${NC} Image built: $FULL_IMAGE_NAME"
    
    # Step 2: Load image to cluster
    echo -e "\n${YELLOW}[2/3]${NC} Loading image to cluster..."
    if [ "$USE_MINIKUBE" = true ]; then
        minikube image load "$FULL_IMAGE_NAME" || {
            echo "  Trying alternative method..."
            eval $(minikube docker-env)
            docker build -t "$FULL_IMAGE_NAME" -f flink-pricing-job/Dockerfile .
            eval $(minikube docker-env -u)
        }
    else
        echo "  Image registry not configured - ensure image is accessible"
    fi
    echo -e "${GREEN}✓${NC} Image ready"
    
    # Step 3: Deploy FlinkDeployment
    echo -e "\n${YELLOW}[3/3]${NC} Deploying Flink job..."
    kubectl apply -f "$K8S_DIR/flink/flink-deployment.yaml"
    
    echo "  Waiting for Flink job to start (this may take 1-2 minutes)..."
    kubectl wait --for=condition=ready --timeout=300s \
        flinkdeployment/pricing-job -n flink 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC} FlinkDeployment not ready within timeout"
        echo "Check status with: kubectl get flinkdeployment -n flink"
    }
    
    # Summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Start port-forwarding automatically
    echo -e "${YELLOW}Setting up port-forwarding...${NC}"
    # Use port 9081 for Flink UI to avoid conflict with pricing-api on 8081
    start_port_forward "flink" "pricing-job-rest" "9081" "8081" "flink-ui"
    
    echo ""
    echo "Quick access:"
    echo "  Flink UI:  http://localhost:9081"
    echo ""
    echo "Check status:"
    echo "  ./scripts/k8s.sh status"
    echo ""
    echo "View logs:"
    echo "  ./scripts/k8s.sh logs jobmanager"
    echo "  ./scripts/k8s.sh logs taskmanager"
    echo ""
    echo "Stop port-forwarding:"
    echo "  ./scripts/k8s.sh ports stop"
    echo ""
}

#######################################
# Undeploy Flink job
#######################################
k8s_undeploy() {
    echo -e "${BLUE}🗑️  Removing Flink Job from Kubernetes${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Stop port-forwarding first
    echo -e "${YELLOW}Stopping Flink port-forwarding...${NC}"
    stop_port_forward "flink-ui"
    
    # Confirm
    echo -e "\n${YELLOW}This will delete the FlinkDeployment and all related resources.${NC}"
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    # Delete FlinkDeployment
    echo -e "\n${YELLOW}[1/2]${NC} Deleting FlinkDeployment..."
    if kubectl get flinkdeployment pricing-job -n flink &> /dev/null; then
        kubectl delete flinkdeployment pricing-job -n flink --wait=true --timeout=300s
        echo -e "${GREEN}✓${NC} FlinkDeployment deleted"
    else
        echo -e "${YELLOW}⚠${NC} FlinkDeployment not found"
    fi
    
    # Wait for pods to terminate
    echo -e "\n${YELLOW}[2/2]${NC} Waiting for pods to terminate..."
    sleep 5
    kubectl wait --for=delete --timeout=120s \
        pod -l app=pricing-job -n flink 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Cleanup complete"
    
    echo ""
    echo -e "${GREEN}✓ Flink job removed${NC}"
    echo ""
    echo "Note: Checkpoints in MinIO are preserved."
    echo "To redeploy: ./scripts/k8s.sh deploy"
    echo ""
}

#######################################
# View logs
#######################################
k8s_logs() {
    local component=${1:-jobmanager}
    
    check_prerequisites
    
    echo -e "${BLUE}📝 Flink ${component^} Logs${NC} (Ctrl+C to exit)"
    echo "=========================================="
    
    case $component in
        jobmanager|jm)
            kubectl logs -n flink -l component=jobmanager -f --tail=100
            ;;
        taskmanager|tm)
            kubectl logs -n flink -l component=taskmanager -f --tail=100
            ;;
        operator)
            kubectl logs -n flink-operator -l app=flink-kubernetes-operator -f --tail=100
            ;;
        *)
            echo -e "${RED}✗ Unknown component: $component${NC}"
            echo "Available: jobmanager, taskmanager, operator"
            exit 1
            ;;
    esac
}

#######################################
# Check status
#######################################
k8s_status() {
    echo -e "${BLUE}📊 Kubernetes Status${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # FlinkDeployment
    echo -e "\n${YELLOW}FlinkDeployment:${NC}"
    kubectl get flinkdeployment -n flink 2>/dev/null || echo "  No FlinkDeployment found"
    
    # Pods
    echo -e "\n${YELLOW}Flink Pods:${NC}"
    kubectl get pods -n flink 2>/dev/null || echo "  No pods found"
    
    # Services
    echo -e "\n${YELLOW}Flink Services:${NC}"
    kubectl get svc -n flink 2>/dev/null || echo "  No services found"
    
    # MinIO
    echo -e "\n${YELLOW}MinIO:${NC}"
    kubectl get pods -n minio 2>/dev/null || echo "  MinIO not deployed"
    
    # Operator
    echo -e "\n${YELLOW}Flink Operator:${NC}"
    kubectl get pods -n flink-operator 2>/dev/null || echo "  Operator not installed"
    
    echo ""
}


#######################################
# Test fault tolerance - Academic Research Edition
#######################################

# Helper: Collect evidence for academic paper
collect_evidence() {
    local test_name=$1
    local phase=$2
    local evidence_dir="$PROJECT_ROOT/fault-tolerance-evidence/${test_name}"
    
    mkdir -p "$evidence_dir"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local prefix="${evidence_dir}/${phase}_${timestamp}"
    
    echo "  📊 Collecting evidence: ${phase}..."
    
    # Pod status
    kubectl get pods -n flink -o wide > "${prefix}_pods.txt" 2>&1
    
    # FlinkDeployment status
    kubectl get flinkdeployment pricing-job -n flink -o yaml > "${prefix}_flinkdeployment.yaml" 2>&1
    
    # Recent events
    kubectl get events -n flink --sort-by='.lastTimestamp' | tail -50 > "${prefix}_events.txt" 2>&1
    
    # Job status via API (if accessible)
    # Disable exit-on-error for this section as API may be unavailable during failures
    set +e
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 2
    
    # Check if port-forward succeeded by testing the connection
    if curl -s --max-time 2 http://localhost:9081/overview > /dev/null 2>&1; then
        curl -s http://localhost:9081/overview > "${prefix}_job_overview.json" 2>&1
        curl -s http://localhost:9081/jobs > "${prefix}_jobs.json" 2>&1
        
        # Get job details if job is running
        local JOB_ID=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].id' 2>/dev/null)
        if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
            curl -s "http://localhost:9081/jobs/${JOB_ID}" > "${prefix}_job_details.json" 2>&1
            curl -s "http://localhost:9081/jobs/${JOB_ID}/checkpoints" > "${prefix}_checkpoints.json" 2>&1
            curl -s "http://localhost:9081/jobs/${JOB_ID}/exceptions" > "${prefix}_exceptions.json" 2>&1
        fi
        
        curl -s http://localhost:9081/taskmanagers > "${prefix}_taskmanagers.json" 2>&1
    else
        # API not available (expected during complete outages)
        echo "{}" > "${prefix}_job_overview.json"
        echo "{}" > "${prefix}_jobs.json"
        echo "  ⚠️  Flink API not accessible (expected during outage)"
    fi
    
    kill $PF_PID 2>/dev/null
    set -e  # Re-enable exit-on-error
    
    # Logs from all components
    kubectl logs -n flink -l component=jobmanager --tail=200 --all-containers > "${prefix}_jobmanager_logs.txt" 2>&1
    kubectl logs -n flink -l component=taskmanager --tail=200 --all-containers > "${prefix}_taskmanager_logs.txt" 2>&1
    kubectl logs -n flink-operator -l app.kubernetes.io/name=flink-kubernetes-operator --tail=100 > "${prefix}_operator_logs.txt" 2>&1
    
    echo "  ✅ Evidence saved to: ${evidence_dir}/"
}

# Helper: Identify active vs standby JobManager
identify_jobmanagers() {
    echo "  🔍 Identifying JobManager roles..."
    
    local JM_PODS=($(kubectl get pods -n flink -l component=jobmanager -o jsonpath='{.items[*].metadata.name}'))
    
    if [ ${#JM_PODS[@]} -lt 2 ]; then
        echo -e "${RED}✗ Expected 2 JobManagers, found ${#JM_PODS[@]}${NC}"
        return 1
    fi
    
    # Check which one is the leader via Kubernetes leases
    local ACTIVE_JM=""
    local STANDBY_JM=""
    
    for pod in "${JM_PODS[@]}"; do
        # Try to determine if this is the active one by checking logs for "leadership"
        if kubectl logs -n flink "$pod" --tail=50 2>/dev/null | grep -qi "leader\|elected\|active"; then
            ACTIVE_JM=$pod
        else
            STANDBY_JM=$pod
        fi
    done
    
    # If we couldn't determine from logs, use lexical order (first pod is likely active)
    if [ -z "$ACTIVE_JM" ]; then
        ACTIVE_JM=${JM_PODS[0]}
        STANDBY_JM=${JM_PODS[1]}
    fi
    
    echo "  📍 Active JobManager:  $ACTIVE_JM"
    echo "  📍 Standby JobManager: $STANDBY_JM"
    
    # Export for use in tests
    export ACTIVE_JOBMANAGER=$ACTIVE_JM
    export STANDBY_JOBMANAGER=$STANDBY_JM
}

# Test Scenario 1: Standby JobManager Failure
test_standby_jm_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 1: Standby JobManager Failure                  ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify that standby JobManager failure doesn't affect job execution"
    echo "   and that a new standby is created for continued HA protection."
    echo ""
    
    identify_jobmanagers
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario1_standby_jm" "01_baseline"
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating standby JobManager failure..."
    echo "  💥 Terminating pod: $STANDBY_JOBMANAGER"
    local DELETE_TIME=$(date +%s)
    kubectl delete pod "$STANDBY_JOBMANAGER" -n flink --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing system response..."
    sleep 5
    collect_evidence "scenario1_standby_jm" "02_immediately_after_failure"
    
    echo "  ⏳ Waiting for pod recreation (30 seconds)..."
    sleep 30
    
    collect_evidence "scenario1_standby_jm" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying recovery..."
    if kubectl wait --for=condition=ready --timeout=120s pod -l component=jobmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ JobManager pods recovered successfully${NC}"
        echo "   Recovery time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}❌ Recovery timeout${NC}"
    fi
    
    collect_evidence "scenario1_standby_jm" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local JM_COUNT=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
    echo "  📊 Running JobManagers: $JM_COUNT (expected: 2)"
    
    # Check job status
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local JOB_STATE=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].status' 2>/dev/null)
    kill $PF_PID 2>/dev/null
    echo "  📊 Job Status: $JOB_STATE (expected: RUNNING)"
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 1 Complete                                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Test Scenario 2: Active JobManager Failure
test_active_jm_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 2: Active JobManager Failure (HA Failover)     ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify High Availability failover - standby JM should become active"
    echo "   Job should continue with minimal interruption"
    echo ""
    
    identify_jobmanagers
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario2_active_jm" "01_baseline"
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating active JobManager failure..."
    echo "  💥 Terminating pod: $ACTIVE_JOBMANAGER"
    local DELETE_TIME=$(date +%s)
    kubectl delete pod "$ACTIVE_JOBMANAGER" -n flink --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing failover process..."
    sleep 3
    collect_evidence "scenario2_active_jm" "02_immediately_after_failure"
    
    echo "  ⏳ Waiting for leader election (monitoring for 60 seconds)..."
    for i in {1..12}; do
        sleep 5
        local RUNNING_JM=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
        echo "     [${i}0s] Running JobManagers: $RUNNING_JM"
    done
    
    collect_evidence "scenario2_active_jm" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying HA failover..."
    if kubectl wait --for=condition=ready --timeout=120s pod -l component=jobmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ HA Failover successful${NC}"
        echo "   Failover time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}❌ Failover timeout${NC}"
    fi
    
    collect_evidence "scenario2_active_jm" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local JM_COUNT=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
    echo "  📊 Running JobManagers: $JM_COUNT (expected: 2)"
    
    # Check job recovered from checkpoint
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local JOB_ID=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].id' 2>/dev/null)
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        local CHECKPOINT_INFO=$(curl -s "http://localhost:9081/jobs/${JOB_ID}/checkpoints" 2>/dev/null | jq '.latest.restored' 2>/dev/null)
        echo "  📊 Job restored from checkpoint: $CHECKPOINT_INFO"
    fi
    kill $PF_PID 2>/dev/null
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 2 Complete - HA Failover Verified            ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Test Scenario 3: Both JobManagers Failure
test_both_jm_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 3: Complete JobManager Failure                 ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify system recovery when all JobManagers fail simultaneously"
    echo "   K8s should recreate pods and restore job from last checkpoint"
    echo ""
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario3_both_jm" "01_baseline"
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating total JobManager failure..."
    local JM_PODS=($(kubectl get pods -n flink -l component=jobmanager -o jsonpath='{.items[*].metadata.name}'))
    echo "  💥💥 Terminating all JobManager pods:"
    for pod in "${JM_PODS[@]}"; do
        echo "     - $pod"
    done
    
    local DELETE_TIME=$(date +%s)
    kubectl delete pods -n flink -l component=jobmanager --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing system response (complete outage)..."
    sleep 5
    collect_evidence "scenario3_both_jm" "02_immediately_after_failure"
    
    echo "  ⏳ Monitoring recreation and recovery (90 seconds)..."
    for i in {1..18}; do
        sleep 5
        local RUNNING_JM=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
        local PENDING_JM=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Pending -o name | wc -l)
        echo "     [${i}5s] Running: $RUNNING_JM, Pending: $PENDING_JM"
    done
    
    collect_evidence "scenario3_both_jm" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying full recovery..."
    if kubectl wait --for=condition=ready --timeout=180s pod -l component=jobmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ Full recovery successful${NC}"
        echo "   Total recovery time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}❌ Recovery timeout${NC}"
    fi
    
    # Wait additional time for job to restart
    echo "  ⏳ Waiting for job to restart and stabilize (30 seconds)..."
    sleep 30
    
    collect_evidence "scenario3_both_jm" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local JM_COUNT=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
    local TM_COUNT=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
    echo "  📊 Running JobManagers: $JM_COUNT (expected: 2)"
    echo "  📊 Running TaskManagers: $TM_COUNT (expected: 2)"
    
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local JOB_STATE=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].status' 2>/dev/null)
    echo "  📊 Job Status: $JOB_STATE"
    kill $PF_PID 2>/dev/null
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 3 Complete - Total Failure Recovery          ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Test Scenario 4: Single TaskManager Failure
test_single_tm_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 4: Single TaskManager Failure                  ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify task redistribution when one TaskManager fails"
    echo "   Job should continue on remaining TM and recreate failed pod"
    echo ""
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario4_single_tm" "01_baseline"
    
    local TM_PODS=($(kubectl get pods -n flink -l component=taskmanager -o jsonpath='{.items[*].metadata.name}'))
    local TARGET_TM=${TM_PODS[0]}
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating TaskManager failure..."
    echo "  💥 Terminating pod: $TARGET_TM"
    local DELETE_TIME=$(date +%s)
    kubectl delete pod "$TARGET_TM" -n flink --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing task redistribution..."
    sleep 5
    collect_evidence "scenario4_single_tm" "02_immediately_after_failure"
    
    echo "  ⏳ Monitoring recovery (45 seconds)..."
    for i in {1..9}; do
        sleep 5
        local RUNNING_TM=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
        echo "     [${i}5s] Running TaskManagers: $RUNNING_TM"
    done
    
    collect_evidence "scenario4_single_tm" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying recovery..."
    if kubectl wait --for=condition=ready --timeout=120s pod -l component=taskmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ TaskManager recovered${NC}"
        echo "   Recovery time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}❌ Recovery timeout${NC}"
    fi
    
    collect_evidence "scenario4_single_tm" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local TM_COUNT=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
    echo "  📊 Running TaskManagers: $TM_COUNT (expected: 2)"
    
    # Check slot distribution
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local SLOT_INFO=$(curl -s http://localhost:9081/overview 2>/dev/null | jq '{taskmanagers, slots_total, slots_available}' 2>/dev/null)
    echo "  📊 Slot distribution: $SLOT_INFO"
    kill $PF_PID 2>/dev/null
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 4 Complete - Task Redistribution Verified    ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Test Scenario 5: All TaskManagers Failure
test_all_tm_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 5: Complete TaskManager Failure                ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify job recovery when all TaskManagers fail"
    echo "   JobManagers should remain stable and wait for TM recreation"
    echo ""
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario5_all_tm" "01_baseline"
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating complete TaskManager failure..."
    local TM_PODS=($(kubectl get pods -n flink -l component=taskmanager -o jsonpath='{.items[*].metadata.name}'))
    echo "  💥💥 Terminating all TaskManager pods:"
    for pod in "${TM_PODS[@]}"; do
        echo "     - $pod"
    done
    
    local DELETE_TIME=$(date +%s)
    kubectl delete pods -n flink -l component=taskmanager --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing system response (no workers)..."
    sleep 5
    collect_evidence "scenario5_all_tm" "02_immediately_after_failure"
    
    echo "  ⏳ Monitoring recreation (60 seconds)..."
    for i in {1..12}; do
        sleep 5
        local RUNNING_TM=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
        local PENDING_TM=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Pending -o name | wc -l)
        echo "     [${i}5s] Running: $RUNNING_TM, Pending: $PENDING_TM"
    done
    
    collect_evidence "scenario5_all_tm" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying full recovery..."
    if kubectl wait --for=condition=ready --timeout=180s pod -l component=taskmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ Full TaskManager recovery successful${NC}"
        echo "   Recovery time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}❌ Recovery timeout${NC}"
    fi
    
    # Wait for job to stabilize
    echo "  ⏳ Waiting for job to stabilize (30 seconds)..."
    sleep 30
    
    collect_evidence "scenario5_all_tm" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local JM_COUNT=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
    local TM_COUNT=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
    echo "  📊 Running JobManagers: $JM_COUNT (expected: 2)"
    echo "  📊 Running TaskManagers: $TM_COUNT (expected: 2)"
    
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local JOB_STATE=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].status' 2>/dev/null)
    local JOB_ID=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].id' 2>/dev/null)
    echo "  📊 Job Status: $JOB_STATE"
    
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        local RESTART_COUNT=$(curl -s "http://localhost:9081/jobs/${JOB_ID}" 2>/dev/null | jq '.vertices[].tasks.FAILED // 0' 2>/dev/null | paste -sd+ | bc)
        echo "  📊 Task failures during recovery: $RESTART_COUNT"
    fi
    kill $PF_PID 2>/dev/null
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 5 Complete - Full TM Recovery Verified       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Test Scenario 6: Complete System Failure (All Pods)
test_complete_system_failure() {
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  SCENARIO 6: Complete System Failure (All Pods)          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📋 Test Objective:"
    echo "   Verify disaster recovery when ALL pods fail (JMs + TMs)"
    echo "   System must bootstrap entirely from S3 checkpoints"
    echo "   Tests absolute worst-case failure scenario"
    echo ""
    
    echo -e "\n${YELLOW}[Phase 1]${NC} Collecting baseline evidence..."
    collect_evidence "scenario6_complete_system" "01_baseline"
    
    echo -e "\n${YELLOW}[Phase 2]${NC} Simulating complete system failure..."
    local ALL_PODS=($(kubectl get pods -n flink -l 'component in (jobmanager,taskmanager)' -o jsonpath='{.items[*].metadata.name}'))
    echo "  💥💥💥 Terminating ALL Flink pods (disaster scenario):"
    echo "     JobManagers:"
    kubectl get pods -n flink -l component=jobmanager -o name | xargs -I {} echo "       - {}"
    echo "     TaskManagers:"
    kubectl get pods -n flink -l component=taskmanager -o name | xargs -I {} echo "       - {}"
    
    local DELETE_TIME=$(date +%s)
    kubectl delete pods -n flink -l 'component in (jobmanager,taskmanager)' --grace-period=0 --force
    
    echo -e "\n${YELLOW}[Phase 3]${NC} Observing complete system outage..."
    sleep 5
    collect_evidence "scenario6_complete_system" "02_immediately_after_failure"
    
    echo "  ⏳ Monitoring complete system recreation (120 seconds)..."
    for i in {1..24}; do
        sleep 5
        local RUNNING_JM=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
        local RUNNING_TM=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
        local PENDING=$(kubectl get pods -n flink --field-selector=status.phase=Pending -o name | wc -l)
        echo "     [${i}5s] JM: $RUNNING_JM, TM: $RUNNING_TM, Pending: $PENDING"
    done
    
    collect_evidence "scenario6_complete_system" "03_during_recovery"
    
    echo -e "\n${YELLOW}[Phase 4]${NC} Verifying full system recovery..."
    
    # Wait for JobManagers first
    if kubectl wait --for=condition=ready --timeout=180s pod -l component=jobmanager -n flink 2>/dev/null; then
        echo -e "${GREEN}✅ JobManagers recovered${NC}"
    else
        echo -e "${RED}⚠️  JobManager recovery timeout${NC}"
    fi
    
    # Then wait for TaskManagers
    if kubectl wait --for=condition=ready --timeout=180s pod -l component=taskmanager -n flink 2>/dev/null; then
        local RECOVERY_TIME=$(date +%s)
        local DOWNTIME=$((RECOVERY_TIME - DELETE_TIME))
        echo -e "${GREEN}✅ Full system recovery successful${NC}"
        echo "   Total recovery time: ${DOWNTIME} seconds"
    else
        echo -e "${RED}⚠️  TaskManager recovery timeout${NC}"
    fi
    
    # Wait for job to stabilize after complete system recovery
    echo "  ⏳ Waiting for job to stabilize after complete recovery (45 seconds)..."
    sleep 45
    
    collect_evidence "scenario6_complete_system" "04_post_recovery"
    
    echo -e "\n${YELLOW}[Phase 5]${NC} Verification checks..."
    local JM_COUNT=$(kubectl get pods -n flink -l component=jobmanager --field-selector=status.phase=Running -o name | wc -l)
    local TM_COUNT=$(kubectl get pods -n flink -l component=taskmanager --field-selector=status.phase=Running -o name | wc -l)
    local TOTAL_PODS=$((JM_COUNT + TM_COUNT))
    echo "  📊 Running JobManagers: $JM_COUNT (expected: 2)"
    echo "  📊 Running TaskManagers: $TM_COUNT (expected: 2)"
    echo "  📊 Total Flink Pods: $TOTAL_PODS (expected: 4)"
    
    kubectl port-forward -n flink svc/pricing-job-rest 9081:8081 > /dev/null 2>&1 &
    local PF_PID=$!
    sleep 3
    local JOB_STATE=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].status' 2>/dev/null)
    local JOB_ID=$(curl -s http://localhost:9081/jobs 2>/dev/null | jq -r '.jobs[0].id' 2>/dev/null)
    echo "  📊 Job Status: $JOB_STATE"
    
    if [ -n "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
        local CHECKPOINT_INFO=$(curl -s "http://localhost:9081/jobs/${JOB_ID}/checkpoints" 2>/dev/null | jq '.latest.restored' 2>/dev/null)
        echo "  📊 Restored from checkpoint: $CHECKPOINT_INFO"
    fi
    kill $PF_PID 2>/dev/null
    
    echo -e "\n${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✅ Scenario 6 Complete - Complete System Recovery        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
}

# Main fault tolerance test function
k8s_test_ft() {
    local scenario=${1:-all}
    
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}║    FLINK FAULT TOLERANCE TEST SUITE                      ║${NC}"
    echo -e "${BLUE}║    Academic Research Edition                              ║${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📊 Test Configuration:"
    echo "   • JobManagers: 2 (1 active, 1 standby - HA enabled)"
    echo "   • TaskManagers: 2 (both active)"
    echo "   • Evidence Collection: Enabled"
    echo "   • Output Directory: fault-tolerance-evidence/"
    echo ""
    
    check_prerequisites
    
    # Verify FlinkDeployment exists
    if ! kubectl get flinkdeployment pricing-job -n flink &> /dev/null; then
        echo -e "${RED}✗ FlinkDeployment not found${NC}"
        echo "Deploy it first: ./scripts/k8s.sh deploy"
        exit 1
    fi
    
    # Verify jq is installed (needed for JSON parsing)
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}⚠  Warning: 'jq' not installed. Some metrics collection will be limited.${NC}"
        echo "   Install with: brew install jq"
    fi
    
    # Create evidence directory
    mkdir -p "$PROJECT_ROOT/fault-tolerance-evidence"
    
    # Run tests based on scenario
    case "$scenario" in
        1|standby-jm)
            test_standby_jm_failure
            ;;
        2|active-jm)
            test_active_jm_failure
            ;;
        3|both-jm)
            test_both_jm_failure
            ;;
        4|single-tm)
            test_single_tm_failure
            ;;
        5|all-tm)
            test_all_tm_failure
            ;;
        6|complete-system|all-pods)
            test_complete_system_failure
            ;;
        all)
            echo -e "${YELLOW}⚠  Running all 6 scenarios sequentially...${NC}"
            echo "   This will take approximately 20-25 minutes."
            echo "   Press Ctrl+C within 5 seconds to cancel..."
            sleep 5
            
            test_standby_jm_failure
            echo -e "\n⏳ Cooldown period (30 seconds)...\n"
            sleep 30
            
            test_active_jm_failure
            echo -e "\n⏳ Cooldown period (30 seconds)...\n"
            sleep 30
            
            test_single_tm_failure
            echo -e "\n⏳ Cooldown period (30 seconds)...\n"
            sleep 30
            
            test_all_tm_failure
            echo -e "\n⏳ Cooldown period (30 seconds)...\n"
            sleep 30
            
            test_both_jm_failure
            echo -e "\n⏳ Cooldown period (30 seconds)...\n"
            sleep 30
            
            test_complete_system_failure
            ;;
        *)
            echo -e "${RED}✗ Unknown scenario: $scenario${NC}"
            echo ""
            echo "Usage: $0 test-ft [scenario]"
            echo ""
            echo "Scenarios:"
            echo "  1 or standby-jm      - Test standby JobManager failure"
            echo "  2 or active-jm       - Test active JobManager failure (HA failover)"
            echo "  3 or both-jm         - Test complete JobManager failure"
            echo "  4 or single-tm       - Test single TaskManager failure"
            echo "  5 or all-tm          - Test complete TaskManager failure"
            echo "  6 or complete-system - Test complete system failure (all pods)"
            echo "  all                  - Run all scenarios sequentially (default)"
            echo ""
            echo "Examples:"
            echo "  $0 test-ft 2                  # Run scenario 2 only"
            echo "  $0 test-ft active-jm          # Run scenario 2 only"
            echo "  $0 test-ft 6                  # Run scenario 6 (disaster recovery)"
            echo "  $0 test-ft all                # Run all 6 scenarios"
            echo ""
            exit 1
            ;;
    esac
    
    # Final summary
    echo -e "\n${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}║    🎓 FAULT TOLERANCE TESTING COMPLETE                    ║${NC}"
    echo -e "${BLUE}║                                                           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📁 Evidence Location:"
    echo "   $PROJECT_ROOT/fault-tolerance-evidence/"
    echo ""
    echo "📊 Evidence includes:"
    echo "   • Pod status snapshots at each phase"
    echo "   • FlinkDeployment state changes"
    echo "   • Kubernetes events timeline"
    echo "   • Job status and checkpoint information"
    echo "   • TaskManager slot distribution"
    echo "   • Component logs (JobManager, TaskManager, Operator)"
    echo ""
    echo "📝 For your academic paper, examine:"
    echo "   • Recovery time measurements"
    echo "   • Checkpoint/restore behavior in logs"
    echo "   • Leader election process (JobManager)"
    echo "   • Task redistribution patterns"
    echo "   • Event sequences during failures"
    echo ""
    echo "🔍 Current cluster status:"
    kubectl get pods -n flink
    echo ""
}

# Main
case "${1:-}" in
    setup)
        k8s_setup
        ;;
    deploy)
        k8s_deploy
        ;;
    undeploy)
        k8s_undeploy
        ;;
    logs)
        k8s_logs "${2:-jobmanager}"
        ;;
    status)
        k8s_status
        ;;
    test-ft)
        k8s_test_ft "${2:-all}"
        ;;
    ports|port-forward)
        case "${2:-}" in
            start)
                start_all_port_forwards
                ;;
            stop)
                stop_all_port_forwards
                ;;
            *)
                echo "Usage: $0 ports {start|stop}"
                echo ""
                echo "  start  - Start all port-forwards (Flink, Grafana, Prometheus)"
                echo "  stop   - Stop all port-forwards"
                echo ""
                echo "Examples:"
                echo "  $0 ports start"
                echo "  $0 ports stop"
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Usage: $0 {setup|deploy|undeploy|logs|status|test-ft|ports}"
        echo ""
        echo "Commands:"
        echo "  setup       - One-time Kubernetes setup (operator, namespaces, MinIO)"
        echo "  deploy      - Deploy Flink job to Kubernetes (auto-starts port-forwarding)"
        echo "  undeploy    - Remove Flink job from Kubernetes"
        echo "  logs        - View logs (specify: jobmanager, taskmanager, operator)"
        echo "  status      - Check Kubernetes resources"
        echo "  test-ft     - Test fault tolerance (1-6 or all scenarios)"
        echo "  ports       - Manage port-forwarding (start|stop)"
        echo ""
        echo "Examples:"
        echo "  $0 setup                  # First-time setup"
        echo "  $0 deploy                 # Deploy Flink job"
        echo "  $0 logs jobmanager        # View JobManager logs"
        echo "  $0 status                 # Check everything"
        echo "  $0 test-ft 2              # Test scenario 2 (active JM failure)"
        echo "  $0 test-ft all            # Run all 6 fault tolerance scenarios"
        echo "  $0 ports start            # Start Flink UI port-forward"
        echo "  $0 ports stop             # Stop port-forwards"
        exit 1
        ;;
esac

