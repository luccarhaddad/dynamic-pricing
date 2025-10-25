# Running the Dynamic Pricing System

## Quick Start

### Prerequisites
- Java 17+
- Docker & Docker Compose
- Ports available: 5432, 8080, 8081, 8082, 9093, 19092

### Start Everything

```bash
./start-all.sh
```

This will:
1. ✅ Start Kafka and PostgreSQL in Docker
2. ✅ Create required Kafka topics (ride-requests, driver-heartbeats, price-updates)
3. ✅ Build all applications
4. ✅ Start Pricing API (port 8081)
5. ✅ Start Flink Job
6. ✅ Start Event Generator (port 8082)

### Stop Everything

```bash
./stop-all.sh
```

---

## Manual Step-by-Step Guide

### 1. Start Infrastructure

```bash
cd infra
docker compose up -d
```

Wait 30-40 seconds for Kafka to be fully ready.

### 2. Create Kafka Topics

```bash
cd infra
./reset-topics.sh
```

Verify topics:
```bash
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:19092 --list
```

### 3. Build Applications

```bash
# Build everything
./gradlew clean build

# Or build individually
./gradlew :flink-pricing-job:shadowJar
./gradlew :services:pricing-api:bootJar
./gradlew :services:event-generator:bootJar
```

### 4. Start Pricing API

```bash
./gradlew :services:pricing-api:bootRun
```

Verify: http://localhost:8081/api/v1/health

### 5. Start Flink Job

```bash
java -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar
```

Expected logs:
```
Starting Dynamic Pricing Flink Job
Connecting to Kafka at: localhost:19092
Created Kafka sources for ride-requests and driver-heartbeats
Price calculation pipeline configured with Kafka sink to topic: price-updates
```

### 6. Start Event Generator

```bash
./gradlew :services:event-generator:bootRun
```

Expected logs:
```
Initializing simulation with 64 zones, 15 drivers per zone
Published X driver heartbeats
```

---

## Verification

### Check System Status

```bash
# Check all Docker containers
docker compose -f infra/docker-compose.yml ps

# Check Kafka topics and messages
docker compose -f infra/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:19092 \
  --topic price-updates \
  --from-beginning --max-messages 5
```

### Test API Endpoints

```bash
# Get current price for zone 1
curl http://localhost:8081/api/v1/zones/1/price

# Stream real-time price updates (Ctrl+C to stop)
curl -N http://localhost:8081/api/v1/zones/1/stream

# Get historical data
curl "http://localhost:8081/api/v1/zones/1/history?from=0&to=9999999999999"

# Calculate fare quote
curl -X POST http://localhost:8081/api/v1/quote \
  -H "Content-Type: application/json" \
  -d '{
    "originZoneId": 1,
    "estDistanceKm": 5.5,
    "estDurationMin": 15
  }'
```

### View Logs

```bash
# Follow logs in real-time
tail -f logs/pricing-api.log
tail -f logs/flink-job.log
tail -f logs/event-generator.log

# Docker logs
docker compose -f infra/docker-compose.yml logs -f kafka
docker compose -f infra/docker-compose.yml logs -f postgres
```

---

## Access Points

| Service | URL | Description |
|---------|-----|-------------|
| Kafka UI | http://localhost:8080 | Web UI for Kafka management |
| Pricing API | http://localhost:8081 | REST API |
| Event Generator | http://localhost:8082/actuator/health | Metrics endpoint |
| PostgreSQL | localhost:5432 | Database (user: pricing, pass: pricing123) |

---

## Troubleshooting

### Issue: Kafka fails to start or keeps restarting

**Solution 1**: Clean volumes and restart
```bash
cd infra
docker compose down -v
docker compose up -d
```

**Solution 2**: Check if port 19092 is already in use
```bash
lsof -i :19092
# If something is using it, kill it or change the port in docker-compose.yml
```

### Issue: Flink job can't connect to Kafka

**Check**: Kafka is listening on port 19092
```bash
docker compose -f infra/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:19092
```

**Fix**: Set environment variable
```bash
export KAFKA_BROKERS=localhost:19092
java -jar flink-pricing-job/build/libs/flink-pricing-job-1.0.0.jar
```

### Issue: Pricing API shows no data

**Check 1**: Verify price-updates topic has messages
```bash
docker compose -f infra/docker-compose.yml exec kafka \
  /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:19092 \
  --topic price-updates \
  --from-beginning --max-messages 1
```

**Check 2**: Verify Flink is publishing to Kafka (check logs for "price-updates-kafka-sink")
```bash
grep "price-updates" logs/flink-job.log
```

### Issue: PostgreSQL connection refused

**Solution**: Database might not be initialized
```bash
cd infra
docker compose down -v
docker compose up postgres -d
# Wait 10 seconds
docker compose logs postgres
```

### Issue: High memory usage

**Solution**: Reduce parallelism or simulation parameters

In Flink:
```bash
# Edit flink-pricing-job/src/main/java/com/pricing/flink/PricingJobMain.java
# Change PARALLELISM from 4 to 2
```

In Event Generator:
```bash
# Edit services/event-generator/src/main/resources/application.yml
# Reduce drivers-per-zone or increase heartbeat-interval-ms
```

### Issue: Kafka healthcheck fails

The healthcheck might take up to 40 seconds on first start. Check:
```bash
docker compose -f infra/docker-compose.yml logs kafka | grep "Kafka Server started"
```

If you see "Kafka Server started" but healthcheck still fails, the system should work anyway. The healthcheck is just for monitoring.

---

## Configuration

### Kafka Configuration

Location: `infra/docker-compose.yml`

Key settings:
- External port: 19092 (for host machine access)
- Internal port: 9092 (for Docker containers)
- Partitions: 16 per topic
- Replication factor: 1 (single node)

### Application Configuration

**Event Generator**: `services/event-generator/src/main/resources/application.yml`
```yaml
app:
  zones: 64
  heartbeat-interval-ms: 4000
  rides-lambda: 0.6  # Poisson rate
  drivers-per-zone: 15
```

**Pricing API**: `services/pricing-api/src/main/resources/application.yml`
```yaml
spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/pricing
    username: pricing
    password: pricing123
  kafka:
    bootstrap-servers: localhost:19092
```

**Flink Job**: Environment variables
```bash
export KAFKA_BROKERS=localhost:19092
export FLINK_PARALLELISM=4
```

---

## Database Access

```bash
# Connect to PostgreSQL
psql -h localhost -p 5432 -U pricing -d pricing

# Useful queries
SELECT * FROM zone_price_snapshot ORDER BY updated_at DESC LIMIT 10;
SELECT * FROM zone_window_metrics WHERE zone_id = 1 ORDER BY window_start DESC LIMIT 10;
SELECT * FROM fare_config WHERE zone_id = 1;
```

---

## System Architecture

```
Event Generator → Kafka (ride-requests, driver-heartbeats)
                    ↓
              Flink Job (stream processing)
                    ↓
                Kafka (price-updates)
                    ↓
              Pricing API → PostgreSQL
                    ↓
              REST Clients / SSE Streams
```

---

## Performance Notes

- **Latency**: Sub-second pricing updates (typically 200-500ms from event to price)
- **Throughput**: Handles ~10,000 events/second with default configuration
- **Window Size**: 15 seconds (configurable in Flink)
- **Event Rate**: ~960 driver heartbeats every 4 seconds + variable ride requests

---

## Clean Restart

If something goes wrong and you want to start fresh:

```bash
# Stop everything
./stop-all.sh

# Clean all volumes and data
cd infra
docker compose down -v

# Remove logs
rm -rf logs/*

# Rebuild everything
cd ..
./gradlew clean build

# Start fresh
./start-all.sh
```

