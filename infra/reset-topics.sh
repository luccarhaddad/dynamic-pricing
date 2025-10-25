#!/bin/bash
set -e

echo "🚀 Creating Kafka topics with 16 partitions..."

# Wait for Kafka to be ready
echo "⏳ Waiting for Kafka to be ready..."
until docker compose exec kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:19092 --list > /dev/null 2>&1; do
    sleep 2
    echo "   Still waiting for Kafka..."
done

echo "✅ Kafka is ready!"

# Create topics
echo "📝 Creating topic: ride-requests"
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server localhost:19092 \
    --topic ride-requests \
    --partitions 16 \
    --replication-factor 1 \
    --config cleanup.policy=delete \
    --config retention.ms=3600000 || echo "Topic ride-requests might already exist"

echo "📝 Creating topic: driver-heartbeats" 
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server localhost:19092 \
    --topic driver-heartbeats \
    --partitions 16 \
    --replication-factor 1 \
    --config cleanup.policy=delete \
    --config retention.ms=3600000 || echo "Topic driver-heartbeats might already exist"

echo "📝 Creating topic: price-updates"
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
    --create \
    --bootstrap-server localhost:19092 \
    --topic price-updates \
    --partitions 16 \
    --replication-factor 1 \
    --config cleanup.policy=delete \
    --config retention.ms=86400000 || echo "Topic price-updates might already exist"

echo "📋 Listing all topics:"
docker compose exec kafka /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:19092 \
    --list

echo "🎉 Topics created successfully!"
