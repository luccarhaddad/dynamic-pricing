package com.pricing.generator.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pricing.generator.model.DriverHeartbeat;
import com.pricing.generator.model.RideRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.support.SendResult;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;

@Service
public class EventPublisher {

    private static final Logger logger = LoggerFactory.getLogger(EventPublisher.class);

    private final KafkaTemplate<Integer, String> kafkaTemplate;
    private final ObjectMapper objectMapper;

    private static final String RIDE_REQ_TOPIC = "ride-requests";
    private static final String DRIVER_HTB_TOPIC = "driver-heartbeats";

    public EventPublisher(KafkaTemplate<Integer, String> kafkaTemplate, ObjectMapper objectMapper) {
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    public void publishRideRequest(RideRequest request) {
        try {
            String json = objectMapper.writeValueAsString(request);
            CompletableFuture<SendResult<Integer, String>> future =
                    kafkaTemplate.send(RIDE_REQ_TOPIC, request.getZoneId(), json);

            future.whenComplete((result, ex) -> {
                if (ex == null) {
                    logger.debug("Published ride request for zone {}: {}ms, ",
                            request.getZoneId(), request.getTsEvent());
                } else {
                    logger.error("Failed to publish ride request for zone {}: {}",
                            request.getZoneId(), ex.getMessage());
                }
            });
        } catch (Exception e) {
            logger.error("Error serializing ride request: {}", e.getMessage());
        }
    }

    public void publishDriverHeartbeat(DriverHeartbeat heartbeat) {
        try {
            String json = objectMapper.writeValueAsString(heartbeat);
            CompletableFuture<SendResult<Integer, String>> future =
                    kafkaTemplate.send(DRIVER_HTB_TOPIC, heartbeat.getZoneId(), json);

            future.whenComplete((result, ex) -> {
                if (ex == null) {
                    logger.debug("Published driver heartbeat for zone {}: driver={}, status={}",
                            heartbeat.getZoneId(), heartbeat.getDriverId(), heartbeat.getStatus());
                } else {
                    logger.error("Failed to publish driver heartbeat for zone {}: {}",
                            heartbeat.getZoneId(), ex.getMessage());
                }
            });
        } catch (Exception e) {
            logger.error("Error serializing driver heartbeat: {}", e.getMessage());
        }
    }
}
