#!/bin/bash
# k8s.sh - Kubernetes operations
#
# Usage:
#   ./scripts/k8s.sh setup       - One-time setup (operator, namespaces, MinIO)
#   ./scripts/k8s.sh deploy      - Deploy Flink job to Kubernetes
#   ./scripts/k8s.sh undeploy    - Remove Flink job
#   ./scripts/k8s.sh logs        - View logs
#   ./scripts/k8s.sh status      - Check Kubernetes resources
#   ./scripts/k8s.sh monitoring  - Deploy monitoring stack
#   ./scripts/k8s.sh test-ft     - Test fault tolerance

set -e
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K8S_DIR="$PROJECT_ROOT/kubernetes"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl is not installed${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}✗ Cannot connect to Kubernetes cluster${NC}"
        exit 1
    fi
    
    return 0
}

#######################################
# One-time Kubernetes setup
#######################################
k8s_setup() {
    echo -e "${BLUE}🚀 Kubernetes Setup${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Step 1: Install Flink Operator
    echo -e "\n${YELLOW}[1/5]${NC} Installing Flink Kubernetes Operator..."
    echo "  Creating operator namespace..."
    kubectl apply -f "$K8S_DIR/flink-operator/namespace.yaml"
    
    echo "  Installing CRDs and operator..."
    kubectl apply -f "$K8S_DIR/flink-operator/install.yaml"
    
    echo "  Waiting for operator to be ready..."
    kubectl wait --for=condition=established --timeout=60s \
        crd/flinkdeployments.flink.apache.org \
        crd/flinksessionjobs.flink.apache.org || {
        echo -e "${RED}✗ CRDs not ready${NC}"
        exit 1
    }
    
    kubectl wait --for=condition=ready --timeout=120s \
        pod -l app=flink-kubernetes-operator -n flink-operator || {
        echo -e "${YELLOW}⚠${NC} Operator pod not ready, but continuing..."
    }
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
    echo "Check status:"
    echo "  ./scripts/k8s.sh status"
    echo ""
    echo "View logs:"
    echo "  ./scripts/k8s.sh logs jobmanager"
    echo "  ./scripts/k8s.sh logs taskmanager"
    echo ""
    echo "Access Flink UI:"
    echo "  kubectl port-forward -n flink svc/pricing-job-rest 8081:8081"
    echo "  Then open: http://localhost:8081"
    echo ""
}

#######################################
# Undeploy Flink job
#######################################
k8s_undeploy() {
    echo -e "${BLUE}🗑️  Removing Flink Job from Kubernetes${NC}"
    echo "=========================================="
    
    check_prerequisites
    
    # Confirm
    echo -e "${YELLOW}This will delete the FlinkDeployment and all related resources.${NC}"
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
    echo "Access Prometheus:"
    echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "  http://localhost:9090"
    echo ""
    echo "Access Grafana:"
    echo "  kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "  http://localhost:3000 (admin/admin)"
    echo ""
    echo "Or use NodePort (if available):"
    echo "  http://<node-ip>:30002"
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
    *)
        echo "Usage: $0 {setup|deploy|undeploy|logs|status|monitoring|test-ft}"
        echo ""
        echo "Commands:"
        echo "  setup       - One-time Kubernetes setup (operator, namespaces, MinIO)"
        echo "  deploy      - Deploy Flink job to Kubernetes"
        echo "  undeploy    - Remove Flink job from Kubernetes"
        echo "  logs        - View logs (specify: jobmanager, taskmanager, operator)"
        echo "  status      - Check Kubernetes resources"
        echo "  monitoring  - Deploy Prometheus and Grafana"
        echo "  test-ft     - Test fault tolerance"
        echo ""
        echo "Examples:"
        echo "  $0 setup                  # First-time setup"
        echo "  $0 deploy                 # Deploy Flink job"
        echo "  $0 logs jobmanager        # View JobManager logs"
        echo "  $0 status                 # Check everything"
        exit 1
        ;;
esac

