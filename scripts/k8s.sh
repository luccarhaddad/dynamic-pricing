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
    
    # Check if services exist before port-forwarding
    local flink_ready=false
    local monitoring_ready=false
    
    # Flink operator creates service with pattern: <deployment-name>-rest
    if kubectl get svc -n flink pricing-job-rest &> /dev/null; then
        flink_ready=true
    fi
    
    if kubectl get svc -n monitoring grafana &> /dev/null; then
        monitoring_ready=true
    fi
    
    if kubectl get svc -n monitoring prometheus &> /dev/null; then
        monitoring_ready=true
    fi
    
    # Start port-forwards
    if [ "$flink_ready" = true ]; then
        # Use port 9081 for Flink UI to avoid conflict with pricing-api on 8081
        start_port_forward "flink" "pricing-job-rest" "9081" "8081" "flink-ui"
    else
        echo -e "${YELLOW}⚠${NC} Flink not deployed, skipping Flink UI port-forward"
    fi
    
    if [ "$monitoring_ready" = true ]; then
        start_port_forward "monitoring" "grafana" "3001" "3000" "grafana"
        start_port_forward "monitoring" "prometheus" "9090" "9090" "prometheus"
    else
        echo -e "${YELLOW}⚠${NC} Monitoring not deployed, skipping monitoring port-forwards"
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Port Forwards Active${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    if [ "$flink_ready" = true ]; then
        echo "  Flink UI:    http://localhost:9081"
    fi
    if [ "$monitoring_ready" = true ]; then
        echo "  Grafana:     http://localhost:3001 (admin/admin)"
        echo "  Prometheus:  http://localhost:9090"
    fi
    echo ""
    echo "To stop all port-forwards:"
    echo "  ./scripts/k8s.sh ports stop"
    echo ""
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
    
    # Monitoring
    echo -e "\n${YELLOW}Monitoring:${NC}"
    kubectl get pods -n monitoring 2>/dev/null || echo "  Monitoring not deployed"
    
    echo ""
}

#######################################
# Deploy monitoring
#######################################
k8s_monitoring() {
    echo -e "${BLUE}📊 Deploying Monitoring Stack${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Ensure namespace exists
    echo -e "\n${YELLOW}[1/3]${NC} Creating monitoring namespace..."
    kubectl apply -f "$K8S_DIR/namespaces.yaml"
    echo -e "${GREEN}✓${NC} Namespace ready"
    
    # Deploy PVCs for persistence
    echo -e "\n${YELLOW}[2/3]${NC} Creating persistent storage..."
    if [ -f "$K8S_DIR/monitoring/storage-pvcs.yaml" ]; then
        kubectl apply -f "$K8S_DIR/monitoring/storage-pvcs.yaml"
        echo -e "${GREEN}✓${NC} Storage created"
    else
        echo -e "${YELLOW}⚠${NC} storage-pvcs.yaml not found, skipping"
    fi
    
    # Deploy Prometheus and Grafana
    echo -e "\n${YELLOW}[3/3]${NC} Deploying Prometheus and Grafana..."
    kubectl apply -f "$K8S_DIR/monitoring/prometheus-deployment.yaml"
    kubectl apply -f "$K8S_DIR/monitoring/grafana-dashboard-configmap.yaml"
    kubectl apply -f "$K8S_DIR/monitoring/grafana-deployment.yaml"
    
    echo "  Waiting for pods to be ready..."
    kubectl wait --for=condition=ready --timeout=120s \
        pod -l app=prometheus -n monitoring 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC} Prometheus not ready yet"
    }
    kubectl wait --for=condition=ready --timeout=120s \
        pod -l app=grafana -n monitoring 2>/dev/null || {
        echo -e "${YELLOW}⚠${NC} Grafana not ready yet"
    }
    
    echo -e "${GREEN}✓${NC} Monitoring deployed"
    
    # Summary
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}Monitoring Deployed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # Start port-forwarding automatically
    echo -e "${YELLOW}Setting up port-forwarding...${NC}"
    start_port_forward "monitoring" "prometheus" "9090" "9090" "prometheus"
    start_port_forward "monitoring" "grafana" "3001" "3000" "grafana"
    
    echo ""
    echo "Quick access:"
    echo "  Prometheus:  http://localhost:9090"
    echo "  Grafana:     http://localhost:3001 (admin/admin)"
    echo ""
    echo "Or use NodePort (if available):"
    echo "  http://<node-ip>:30002"
    echo ""
    echo "Stop port-forwarding:"
    echo "  ./scripts/k8s.sh ports stop"
    echo ""
}

#######################################
# Test fault tolerance
#######################################
k8s_test_ft() {
    echo -e "${BLUE}🧪 Testing Flink Fault Tolerance${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Check if FlinkDeployment exists
    if ! kubectl get flinkdeployment pricing-job -n flink &> /dev/null; then
        echo -e "${RED}✗ FlinkDeployment not found${NC}"
        echo "Deploy it first: ./scripts/k8s.sh deploy"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} FlinkDeployment found"
    
    # Test 1: TaskManager Pod Failure
    echo -e "\n${YELLOW}[Test 1]${NC} TaskManager Pod Failure"
    echo "----------------------------------------"
    
    TM_POD=$(kubectl get pods -n flink -l component=taskmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$TM_POD" ]; then
        echo -e "${RED}✗ No TaskManager pod found${NC}"
        exit 1
    fi
    
    echo "  Found TaskManager: $TM_POD"
    echo "  Deleting pod to simulate failure..."
    kubectl delete pod "$TM_POD" -n flink --force --grace-period=0
    
    echo "  Waiting for recovery (30 seconds)..."
    sleep 30
    
    if kubectl wait --for=condition=ready --timeout=90s \
        pod -l component=taskmanager -n flink 2>/dev/null; then
        echo -e "${GREEN}✓${NC} TaskManager recovered"
    else
        echo -e "${RED}✗${NC} TaskManager did not recover"
    fi
    
    # Test 2: JobManager Pod Failure
    echo -e "\n${YELLOW}[Test 2]${NC} JobManager Pod Failure"
    echo "----------------------------------------"
    
    JM_POD=$(kubectl get pods -n flink -l component=jobmanager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$JM_POD" ]; then
        echo -e "${RED}✗ No JobManager pod found${NC}"
        exit 1
    fi
    
    echo "  Found JobManager: $JM_POD"
    echo "  Deleting pod to simulate failure..."
    kubectl delete pod "$JM_POD" -n flink --force --grace-period=0
    
    echo "  Waiting for recovery (60 seconds)..."
    sleep 60
    
    if kubectl wait --for=condition=ready --timeout=120s \
        pod -l component=jobmanager -n flink 2>/dev/null; then
        echo -e "${GREEN}✓✓✓ JobManager recovered!${NC}"
    else
        echo -e "${RED}✗${NC} JobManager did not recover"
    fi
    
    # Summary
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Current pod status:"
    kubectl get pods -n flink
    echo ""
    echo "Check logs:"
    echo "  ./scripts/k8s.sh logs jobmanager"
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
    monitoring)
        k8s_monitoring
        ;;
    test-ft)
        k8s_test_ft
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
        echo "Usage: $0 {setup|deploy|undeploy|logs|status|monitoring|test-ft|ports}"
        echo ""
        echo "Commands:"
        echo "  setup       - One-time Kubernetes setup (operator, namespaces, MinIO)"
        echo "  deploy      - Deploy Flink job to Kubernetes (auto-starts port-forwarding)"
        echo "  undeploy    - Remove Flink job from Kubernetes"
        echo "  logs        - View logs (specify: jobmanager, taskmanager, operator)"
        echo "  status      - Check Kubernetes resources"
        echo "  monitoring  - Deploy Prometheus and Grafana (auto-starts port-forwarding)"
        echo "  test-ft     - Test fault tolerance"
        echo "  ports       - Manage port-forwarding (start|stop)"
        echo ""
        echo "Examples:"
        echo "  $0 setup                  # First-time setup"
        echo "  $0 deploy                 # Deploy Flink job"
        echo "  $0 logs jobmanager        # View JobManager logs"
        echo "  $0 status                 # Check everything"
        echo "  $0 ports start            # Start all port-forwards"
        echo "  $0 ports stop             # Stop all port-forwards"
        exit 1
        ;;
esac

