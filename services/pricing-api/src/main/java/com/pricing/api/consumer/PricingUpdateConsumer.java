package com.pricing.api.consumer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pricing.api.dto.ZonePriceResponse;
import com.pricing.api.entity.ZonePriceSnapshot;
import com.pricing.api.entity.ZoneWindowMetrics;
import com.pricing.api.repository.ZonePriceSnapshotRepository;
import com.pricing.api.repository.ZoneWindowMetricsRepository;
import com.pricing.api.service.StreamingService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

@Component
public class PricingUpdateConsumer {
    private static final Logger logger = LoggerFactory.getLogger(PricingUpdateConsumer.class);

    private final ZonePriceSnapshotRepository snapshotRepository;
    private final ZoneWindowMetricsRepository metricsRepository;
    private final StreamingService streamingService;
    private final ObjectMapper objectMapper;

    private static final String KAFKA_TOPIC = "price-updates";
    private static final String GROUP_ID = "pricing-api";

    public PricingUpdateConsumer(ZonePriceSnapshotRepository snapshotRepository,
                                 ZoneWindowMetricsRepository metricsRepository,
                                 StreamingService streamingService,
                                 ObjectMapper objectMapper) {
        this.snapshotRepository = snapshotRepository;
        this.metricsRepository = metricsRepository;
        this.streamingService = streamingService;
        this.objectMapper = objectMapper;
    }

    @KafkaListener(topics = KAFKA_TOPIC, groupId = GROUP_ID)
    @Transactional
    public void consumePriceUpdate(
            @Payload String message,
            @Header(KafkaHeaders.RECEIVED_PARTITION) int partition,
            @Header(KafkaHeaders.RECEIVED_TOPIC) String topic,
            @Header(KafkaHeaders.RECEIVED_TIMESTAMP) long timestamp) {

        try {
            logger.debug("Received price update from {}-{}: {}", topic, partition, message);

            JsonNode priceUpdate = objectMapper.readTree(message);

            Integer zoneId = priceUpdate.get("zone_id").asInt();
            long windowStart = priceUpdate.get("window_start").asLong();
            long windowEnd = priceUpdate.get("window_end").asLong();
            int demand = priceUpdate.get("demand").asInt();
            int supply = priceUpdate.get("supply").asInt();
            BigDecimal ratio = BigDecimal.valueOf(priceUpdate.get("ratio").asDouble());
            BigDecimal surgeMultiplier = BigDecimal.valueOf(priceUpdate.get("surge_multiplier").asDouble());
            long tsCompute = priceUpdate.get("ts_compute").asLong();

            updatePriceSnapshot(zoneId, windowStart, windowEnd, demand, supply, ratio, surgeMultiplier);
            storeHistoricalMetrics(zoneId, windowStart, windowEnd, demand, supply, ratio, surgeMultiplier, tsCompute);
            broadcastToSubscribers(zoneId, surgeMultiplier, demand, supply, ratio);
            
            logger.debug("Successfully processed price update for zone {}", zoneId);

        } catch (Exception e) {
            logger.error("Error processing price update: {}", e.getMessage(), e);
            throw new RuntimeException("Failed to process price update", e);
        }
    }

    private void updatePriceSnapshot(Integer zoneId, long windowStart, long windowEnd,
                                     int demand, int supply, BigDecimal ratio, BigDecimal surgeMultiplier) {

        ZonePriceSnapshot snapshot = snapshotRepository.findById(zoneId)
                .orElse(new ZonePriceSnapshot());

        snapshot.setZoneId(zoneId);
        snapshot.setSurgeMultiplier(surgeMultiplier);
        snapshot.setDemand(demand);
        snapshot.setSupply(supply);
        snapshot.setRatio(ratio);
        snapshot.setWindowStart(OffsetDateTime.ofInstant(Instant.ofEpochMilli(windowStart), ZoneOffset.UTC));
        snapshot.setWindowEnd(OffsetDateTime.ofInstant(Instant.ofEpochMilli(windowEnd), ZoneOffset.UTC));
        snapshot.setUpdatedAt(OffsetDateTime.now());

        snapshotRepository.save(snapshot);
        logger.debug("Updated price snapshot for zone {}", zoneId);
    }

    private void storeHistoricalMetrics(Integer zoneId, long windowStart, long windowEnd,
                                        int demand, int supply, BigDecimal ratio, BigDecimal surgeMultiplier, long tsCompute) {

        ZoneWindowMetrics metrics = new ZoneWindowMetrics(
                zoneId,
                OffsetDateTime.ofInstant(Instant.ofEpochMilli(windowStart), ZoneOffset.UTC),
                OffsetDateTime.ofInstant(Instant.ofEpochMilli(windowEnd), ZoneOffset.UTC),
                demand,
                supply,
                ratio,
                surgeMultiplier
        );

        metrics.setTsCompute(OffsetDateTime.ofInstant(Instant.ofEpochMilli(tsCompute), ZoneOffset.UTC));

        try {
            metricsRepository.save(metrics);
            logger.debug("Stored historical metrics for zone {}", zoneId);
        } catch (Exception e) {
            // This might fail due to duplicate key if Flink sends duplicate messages
            logger.warn("Failed to store historical metrics for zone {}: {}", zoneId, e.getMessage());
        }
    }

    private void broadcastToSubscribers(Integer zoneId, BigDecimal surgeMultiplier, int demand, int supply, BigDecimal ratio) {
        try {
            ZonePriceResponse priceResponse = new ZonePriceResponse(
                    zoneId,
                    surgeMultiplier,
                    null,
                    OffsetDateTime.now(),
                    demand,
                    supply,
                    ratio
            );

            streamingService.broadcastPriceUpdate(zoneId, priceResponse);

        } catch (Exception e) {
            logger.error("Failed to broadcast price update for zone {}: {}", zoneId, e.getMessage());
        }
    }
}
