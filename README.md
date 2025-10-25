# Dynamic Pricing System

A real-time dynamic pricing system for ride-sharing built with Apache Flink, Kafka, Spring Boot, and PostgreSQL.

## 🎯 What This System Does

Calculates surge pricing in real-time based on supply (available drivers) and demand (ride requests) across 16 geographic zones:

1. **Event Generator** simulates ride requests and driver heartbeats
2. **Apache Flink** processes streams in 15-second windows
3. **Pricing Algorithm** calculates surge multipliers (1.0x - 3.0x)
4. **REST API** provides current prices, historical data, and real-time streams
5. **PostgreSQL** stores pricing history and configurations

---

## 🚀 Quick Start

### Prerequisites
- Java 17+
- Docker & Docker Compose
- Ports: 5432, 8080, 8081, 8082, 9093, 19092

### Start the System

```bash
./start-all.sh
```

Wait ~1-2 minutes for everything to start up.

### Verify System is Working

```bash
./verify-system.sh
```

### Test the API

```bash
# Get current price for zone 1
curl http://localhost:8081/api/v1/zones/1/price | jq

# Stream real-time price updates (Ctrl+C to stop)
curl -N http://localhost:8081/api/v1/zones/1/stream

# Get historical pricing data
curl "http://localhost:8081/api/v1/zones/1/history" | jq
```

### Stop the System

```bash
./stop-all.sh
```

### Run Experiments

```bash
# Run deterministic experiments with different failure scenarios
./run-experiment.sh
```

This will run 5 experiments:
1. **Baseline** - No failures
2. **Network Delay** - 100ms artificial delay
3. **Dropped Events** - 10% failure rate
4. **Burst Traffic** - 3x traffic multiplier
5. **Combined Failures** - Multiple issues combined

Results are saved to `experiment-results/` directory.

---

## 📊 System Architecture

```
┌─────────────────┐
│ Event Generator │ (Simulates ride requests & driver heartbeats)
└────────┬────────┘
         │
         ▼
    ┌────────┐
    │ Kafka  │ (ride-requests, driver-heartbeats topics)
    └───┬────┘
        │
        ▼
 ┌──────────────┐
 │  Flink Job   │ (15s windows, aggregate & calculate surge)
 └──────┬───────┘
        │
        ▼
    ┌────────┐
    │ Kafka  │ (price-updates topic)
    └───┬────┘
        │
        ▼
  ┌──────────────┐      ┌──────────────┐
  │ Pricing API  │ ───► │ PostgreSQL   │
  └──────┬───────┘      └──────────────┘
         │
         ▼
  ┌──────────────┐
  │   Clients    │ (REST API, Server-Sent Events)
  └──────────────┘
```

---

## 🌐 Access Points

| Service | URL | Description |
|---------|-----|-------------|
| **Frontend Dashboard** | http://localhost:3000 | Real-time pricing visualization |
| **Kafka UI** | http://localhost:8080 | Monitor Kafka topics and messages |
| **Pricing API** | http://localhost:8081 | REST API for pricing |
| **Event Generator** | http://localhost:8082/actuator/health | Metrics |
| **PostgreSQL** | localhost:5432 | Database (pricing/pricing123) |

---

## 📝 API Endpoints

### Get Current Price
```bash
GET /api/v1/zones/{zoneId}/price
```

Response:
```json
{
  "zoneId": 1,
  "surgeMultiplier": 1.5,
  "quotedFare": null,
  "timestamp": "2025-10-19T15:30:00Z"
}
```

### Stream Real-Time Updates (SSE)
```bash
GET /api/v1/zones/{zoneId}/stream
```

### Get Historical Data
```bash
GET /api/v1/zones/{zoneId}/history?from={epochMs}&to={epochMs}
```

### Calculate Fare Quote
```bash
POST /api/v1/quote
Content-Type: application/json

{
  "originZoneId": 1,
  "estDistanceKm": 5.5,
  "estDurationMin": 15
}
```

### Health Check
```bash
GET /api/v1/health
```

---

## 🔧 Configuration

### Kafka Topics

| Topic | Partitions | Retention | Purpose |
|-------|------------|-----------|---------|
| ride-requests | 16 | 1 hour | Incoming ride requests |
| driver-heartbeats | 16 | 1 hour | Driver availability updates |
| price-updates | 16 | 24 hours | Calculated surge prices |

### Pricing Algorithm

```
if (demand/supply <= 1.0)  → 1.0x  (no surge)
if (demand/supply <= 2.0)  → 1.0x - 1.5x  (linear)
if (demand/supply <= 4.0)  → 1.5x - 2.5x  (slower growth)
if (demand/supply > 4.0)   → 2.5x - 3.0x  (capped at 3.0x)
```

### Simulation Parameters

Edit `services/event-generator/src/main/resources/application.yml`:
```yaml
app:
  zones: 16                    # Number of geographic zones
  drivers-per-zone: 15         # Drivers per zone
  heartbeat-interval-ms: 4000  # How often drivers report location
  rides-lambda: 0.6            # Poisson rate for ride requests

experiment:
  deterministic: true          # Enable deterministic mode for experiments
  seed: 12345                  # Random seed for reproducibility
  scenario: normal             # Experiment scenario
  failure-rate: 0.0            # Simulated failure rate (0.0-1.0)
  network-delay-ms: 0          # Artificial network delay
  burst-multiplier: 1.0        # Traffic burst multiplier
```

---

## 📚 Documentation

- **[RUNNING.md](RUNNING.md)** - Detailed running instructions & troubleshooting
- **[KAFKA_FIXES_SUMMARY.md](KAFKA_FIXES_SUMMARY.md)** - Kafka configuration explained
- **[FIXES_APPLIED.md](FIXES_APPLIED.md)** - Complete list of fixes applied

---

## 🗂️ Project Structure

```
dynamic-pricing/
├── flink-pricing-job/          # Flink stream processing
│   └── src/main/java/com/pricing/flink/
│       ├── PricingJobMain.java         # Main job definition
│       ├── function/                    # Map/FlatMap functions
│       ├── model/                       # Data models
│       └── serializer/                  # Kafka serializers
│
├── services/
│   ├── event-generator/        # Simulates events
│   │   └── src/main/java/com/pricing/generator/
│   │       ├── EventGeneratorApplication.java
│   │       ├── model/                   # Event models
│   │       └── service/                 # Publishing logic
│   │
│   └── pricing-api/            # REST API
│       └── src/main/java/com/pricing/api/
│           ├── PricingApplication.java
│           ├── controller/              # REST endpoints
│           ├── consumer/                # Kafka consumer
│           ├── entity/                  # JPA entities
│           └── service/                 # Business logic
│
├── infra/
│   ├── docker-compose.yml      # Infrastructure setup
│   ├── init-db.sql             # Database schema
│   └── reset-topics.sh         # Topic creation script
│
├── schemas/json/               # JSON schemas
├── start-all.sh                # Start entire system
├── stop-all.sh                 # Stop entire system
└── verify-system.sh            # Health check
```

---

## 🧪 Testing & Monitoring

### Watch Kafka Messages

```bash
# Watch ride requests
docker compose -f infra/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:19092 \
  --topic ride-requests

# Watch price updates
docker compose -f infra/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:19092 \
  --topic price-updates
```

### View Application Logs

```bash
tail -f logs/flink-job.log
tail -f logs/pricing-api.log
tail -f logs/event-generator.log
```

### Query Database

```bash
psql -h localhost -p 5432 -U pricing -d pricing

# Useful queries:
SELECT * FROM zone_price_snapshot ORDER BY updated_at DESC LIMIT 10;
SELECT * FROM zone_window_metrics WHERE zone_id = 1 ORDER BY window_start DESC LIMIT 10;
SELECT * FROM fare_config WHERE zone_id = 1;
```

---

## 🐛 Troubleshooting

### System Won't Start

```bash
# Clean everything and restart
./stop-all.sh
docker compose -f infra/docker-compose.yml down -v
./start-all.sh
```

### Kafka Issues

See **[KAFKA_FIXES_SUMMARY.md](KAFKA_FIXES_SUMMARY.md)** for detailed Kafka troubleshooting.

Common fix:
```bash
cd infra
docker compose down -v
docker compose up -d
./reset-topics.sh
```

### No Price Updates

1. Check Flink logs: `tail -f logs/flink-job.log`
2. Verify events flowing: `./verify-system.sh`
3. Check Kafka consumer lag in Kafka UI: http://localhost:8080

### Database Connection Issues

```bash
docker compose -f infra/docker-compose.yml restart postgres
```

---

## 🔒 Zone Configuration

The system includes 16 zones divided into 4 types:

| Zones | Type | Description | Base Fare |
|-------|------|-------------|-----------|
| 1-4 | DOWNTOWN | Business districts | R$ 8-10 |
| 5-8 | URBAN | Residential/commercial | R$ 5.50-7 |
| 9-12 | SUBURBAN | Residential suburbs | R$ 4-5 |
| 13-16 | AIRPORT | Airport & special routes | R$ 12-15 |

---

## 📈 Performance

- **Latency**: Sub-second pricing updates (typically 200-500ms)
- **Throughput**: ~10,000 events/second with default config
- **Window Size**: 15 seconds
- **Parallelism**: 4 (Flink)
- **Event Rate**: ~960 heartbeats every 4s + variable ride requests

---

## 🚧 Known Limitations

- Single Kafka broker (not production-ready for HA)
- No authentication/authorization
- In-memory SSE (won't persist across restarts)
- No rate limiting
- Simple surge algorithm (could be ML-based)

---

## 🎓 Learning Resources

- [Apache Flink Documentation](https://flink.apache.org/docs/)
- [Apache Kafka Documentation](https://kafka.apache.org/documentation/)
- [Spring Boot + Kafka](https://spring.io/projects/spring-kafka)

---

## 📄 License

This is a demonstration project for learning stream processing with Apache Flink.

---

## 🤝 Contributing

This is a demonstration project. For production use, consider:
- Multi-broker Kafka cluster
- Proper authentication (OAuth2, JWT)
- Rate limiting and caching (Redis)
- Monitoring (Prometheus + Grafana)
- ML-based pricing models
- High availability setup

---

## 📞 Support

If you encounter issues:

1. Run `./verify-system.sh` to identify problem areas
2. Check logs in `logs/` directory
3. Review **[RUNNING.md](RUNNING.md)** for detailed troubleshooting
4. Check **[KAFKA_FIXES_SUMMARY.md](KAFKA_FIXES_SUMMARY.md)** for Kafka issues

---

**Built with ❤️ using Apache Flink, Kafka, Spring Boot, and PostgreSQL**

