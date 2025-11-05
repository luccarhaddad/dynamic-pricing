# Scripts Directory

This directory contains all deployment and management scripts for the dynamic pricing system.

## 📋 Scripts Overview

All scripts have been consolidated into 4 purpose-driven tools:

### 🔧 `dev.sh` - Local Development

Manages local development environment (Docker Compose + Spring Boot services).

```bash
./scripts/dev.sh start      # Start infrastructure and Spring Boot apps
./scripts/dev.sh stop       # Stop services (keep Docker)
./scripts/dev.sh restart    # Full restart with clean state
./scripts/dev.sh logs       # View logs from all services
./scripts/dev.sh logs api   # View logs from specific service
./scripts/dev.sh status     # Check what's running
```

**What it manages:**
- Docker Compose (Kafka, PostgreSQL, Kafka UI)
- Kafka topic creation
- Pricing API (Spring Boot)
- Event Generator (Spring Boot)
- Frontend (Python)

**Does NOT manage:**
- Flink (deployed in Kubernetes via `k8s.sh`)

---

### ☸️ `k8s.sh` - Kubernetes Operations

Manages all Kubernetes deployments including Flink, MinIO, and monitoring.

```bash
./scripts/k8s.sh setup               # One-time setup (operator, namespaces, MinIO)
./scripts/k8s.sh deploy              # Deploy Flink job to Kubernetes
./scripts/k8s.sh undeploy            # Remove Flink job
./scripts/k8s.sh logs jobmanager     # View Flink JobManager logs
./scripts/k8s.sh logs taskmanager    # View Flink TaskManager logs
./scripts/k8s.sh status              # Check K8s resources
./scripts/k8s.sh monitoring          # Deploy Prometheus & Grafana
./scripts/k8s.sh test-ft             # Test fault tolerance
```

**What it manages:**
- Flink Kubernetes Operator
- Flink job deployment
- MinIO (S3-compatible storage)
- Prometheus & Grafana monitoring
- All Kubernetes resources

---

### 🔨 `build.sh` - Build Operations

Builds all application components.

```bash
./scripts/build.sh all      # Build everything
./scripts/build.sh flink    # Build Flink job only
./scripts/build.sh api      # Build Pricing API
./scripts/build.sh gen      # Build Event Generator
./scripts/build.sh clean    # Clean all builds
```

**What it builds:**
- Flink job (shadow JAR)
- Spring Boot applications
- Docker images (if needed)

---

### 🛠️ `utils.sh` - Utilities

Helper utilities for development.

```bash
./scripts/utils.sh check-deps              # Check prerequisites
./scripts/utils.sh port-check              # Check if ports are available
./scripts/utils.sh kafka-topics            # List Kafka topics
./scripts/utils.sh kafka-consume TOPIC     # Consume from Kafka topic
```

---

## 🚀 Quick Start

### First Time Setup

```bash
# 1. Check prerequisites
./scripts/utils.sh check-deps

# 2. Start local infrastructure
./scripts/dev.sh start

# 3. Set up Kubernetes (one-time)
./scripts/k8s.sh setup

# 4. Deploy Flink to Kubernetes
./scripts/k8s.sh deploy

# 5. (Optional) Deploy monitoring
./scripts/k8s.sh monitoring
```

### Daily Development Workflow

```bash
# Start local services
./scripts/dev.sh start

# Deploy/redeploy Flink after changes
./scripts/build.sh flink
./scripts/k8s.sh deploy

# Check status
./scripts/dev.sh status
./scripts/k8s.sh status

# View logs
./scripts/dev.sh logs api
./scripts/k8s.sh logs jobmanager

# Stop everything
./scripts/dev.sh stop
./scripts/k8s.sh undeploy
```

### Full Clean Restart

```bash
# Clean restart with all state cleared
./scripts/dev.sh restart

# Redeploy Flink
./scripts/k8s.sh undeploy
./scripts/k8s.sh deploy
```

---

## 📐 Architecture

The scripts follow a clear separation of concerns:

```
┌─────────────────────────────────────────┐
│         Local Development (dev.sh)      │
├─────────────────────────────────────────┤
│ • Kafka (Docker Compose)                │
│ • PostgreSQL (Docker Compose)           │
│ • Pricing API (Spring Boot)             │
│ • Event Generator (Spring Boot)         │
│ • Frontend (Python)                     │
└─────────────────────────────────────────┘
                  ↕
┌─────────────────────────────────────────┐
│         Kubernetes (k8s.sh)             │
├─────────────────────────────────────────┤
│ • Flink Job (Kubernetes Operator)       │
│ • MinIO (S3-compatible storage)         │
│ • Prometheus (metrics)                  │
│ • Grafana (dashboards)                  │
└─────────────────────────────────────────┘
```

**Why this separation?**
- Local infrastructure (Kafka, PostgreSQL) in Docker is simpler and more resource-efficient for development
- Flink in Kubernetes provides production-like deployment with High Availability, checkpointing to S3, and fault tolerance
- Clear boundaries between local and Kubernetes environments

---

## 🔍 Common Tasks

### Debugging

```bash
# Check what's running
./scripts/dev.sh status
./scripts/k8s.sh status

# View logs
./scripts/dev.sh logs              # All local services
./scripts/dev.sh logs api          # Specific service
./scripts/k8s.sh logs jobmanager   # Flink JobManager
./scripts/k8s.sh logs taskmanager  # Flink TaskManager

# Check Kafka topics
./scripts/utils.sh kafka-topics

# Consume from Kafka
./scripts/utils.sh kafka-consume price-updates
```

### Testing

```bash
# Start an experiment
curl -X POST http://localhost:8081/experiments/simple-surge

# Test Flink fault tolerance
./scripts/k8s.sh test-ft

# Check metrics
# Prometheus: http://localhost:30000
# Grafana: http://localhost:30001 (admin/admin)
```

### Cleanup

```bash
# Stop local services (keeps Docker running)
./scripts/dev.sh stop

# Undeploy Flink from Kubernetes
./scripts/k8s.sh undeploy

# Full restart with clean state
./scripts/dev.sh restart
```

---

## 📦 Service Endpoints

### Local Services (dev.sh)
- **Pricing API**: http://localhost:8081/api/v1/health
- **Event Generator**: http://localhost:8082/actuator/health
- **Frontend**: http://localhost:3000
- **Kafka UI**: http://localhost:8080
- **Kafka**: localhost:19092
- **PostgreSQL**: localhost:5432

### Kubernetes Services (k8s.sh)
- **MinIO Console**: http://localhost:30001
- **Prometheus**: http://localhost:30000
- **Grafana**: http://localhost:30001 (after deploying monitoring)
- **Flink UI**: Via port-forward - `kubectl port-forward -n flink svc/dynamic-pricing-job-rest 8082:8081`

---

## ⚙️ Environment Variables

Scripts respect these environment variables:

- `MINIKUBE_PROFILE`: Minikube profile name (default: `minikube`)
- `KAFKA_BOOTSTRAP_SERVERS`: Kafka connection (default: `localhost:19092`)
- `POSTGRES_HOST`: PostgreSQL host (default: `localhost`)
- `POSTGRES_PORT`: PostgreSQL port (default: `5432`)

---

## 🐛 Troubleshooting

### "Port already in use"

```bash
./scripts/utils.sh port-check
# Kill processes on conflicting ports if needed
./scripts/dev.sh stop
```

### "Kafka topics not found"

```bash
# Topics are auto-created by dev.sh start
# Or manually create:
./scripts/dev.sh start  # Will recreate topics
```

### "Flink job won't deploy"

```bash
# Check Kubernetes status
./scripts/k8s.sh status

# Check operator logs
kubectl logs -n flink-operator -l app.kubernetes.io/name=flink-kubernetes-operator -f

# Redeploy
./scripts/k8s.sh undeploy
./scripts/k8s.sh deploy
```

### "Build failures"

```bash
# Clean build
./scripts/build.sh clean
./scripts/build.sh all
```

---

## 📝 Notes

- All scripts are designed to be **idempotent** (safe to run multiple times)
- Scripts include **color-coded output** for better readability
- Each script has a **help menu** - run without arguments to see usage
- Scripts assume you're running from the **project root directory**
- Most operations include **automatic health checks** and **validation**

---

## 🔄 Migration from Old Scripts

If you're migrating from the old script structure:

| Old Command | New Command |
|-------------|-------------|
| `./scripts/start.sh` | `./scripts/dev.sh start` |
| `./scripts/stop.sh` | `./scripts/dev.sh stop` |
| `./scripts/full-restart.sh` | `./scripts/dev.sh restart` |
| `./scripts/install-flink-operator.sh` | `./scripts/k8s.sh setup` |
| `./scripts/deploy-flink-k8s.sh` | `./scripts/k8s.sh deploy` |
| `./scripts/cleanup-flink-k8s.sh` | `./scripts/k8s.sh undeploy` |
| `./scripts/deploy-monitoring.sh` | `./scripts/k8s.sh monitoring` |
| `./scripts/test-fault-tolerance.sh` | `./scripts/k8s.sh test-ft` |
| `./gradlew build` | `./scripts/build.sh all` |

The old scripts have been removed to reduce complexity and improve maintainability.
