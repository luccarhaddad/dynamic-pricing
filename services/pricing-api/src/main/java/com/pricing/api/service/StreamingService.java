package com.pricing.api.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.pricing.api.dto.ZonePriceResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;

@Service
public class StreamingService {
    private static final Logger logger = LoggerFactory.getLogger(StreamingService.class);

    private final Map<Integer, CopyOnWriteArrayList<SseEmitter>> zoneSubscriptions = new ConcurrentHashMap<>();
    private final CopyOnWriteArrayList<SseEmitter> allZonesSubscribers = new CopyOnWriteArrayList<>();
    private final ObjectMapper objectMapper;
    private static final Long TIMEOUT = 0L; // No timeout - keep connection alive with heartbeats

    public StreamingService(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public SseEmitter subscribeToZone(Integer zoneId) {
        SseEmitter emitter = new SseEmitter(TIMEOUT);

        zoneSubscriptions.computeIfAbsent(zoneId, k -> new CopyOnWriteArrayList<>()).add(emitter);

        emitter.onCompletion(() -> removeSubscription(zoneId, emitter));
        emitter.onTimeout(() -> removeSubscription(zoneId, emitter));
        emitter.onError(throwable -> {
            logger.warn("SSE error for zone {}: {}", zoneId, throwable.getMessage());
            removeSubscription(zoneId, emitter);
        });

        try {
            emitter.send(SseEmitter.event()
                    .name("connected")
                    .data("{\"message\":\"Connected to zone " + zoneId + " price stream\",\"zone_id\":" + zoneId + "}"));
        } catch (IOException e) {
            logger.error("Error sending initial SSE event for zone {}: {}", zoneId, e.getMessage());
            removeSubscription(zoneId, emitter);
        }

        logger.info("New SSE subscription for zone {}. Total subscribers: {}",
                zoneId, zoneSubscriptions.get(zoneId).size());

        return emitter;
    }

    public void broadcastPriceUpdate(Integer zoneId, ZonePriceResponse response) {
        CopyOnWriteArrayList<SseEmitter> subscribers = zoneSubscriptions.get(zoneId);

        try {
            String jsonData = objectMapper.writeValueAsString(response);

            // Broadcast to zone-specific subscribers
            if (subscribers != null && !subscribers.isEmpty()) {
                for (SseEmitter emitter : new CopyOnWriteArrayList<>(subscribers)) {
                    try {
                        emitter.send(SseEmitter.event()
                                .name("price-update")
                                .data(jsonData));
                    } catch (IOException e) {
                        logger.warn("Failed to send price update to subscriber for zone {}: {}", zoneId, e.getMessage());
                        removeSubscription(zoneId, emitter);
                    }
                }
                logger.debug("Broadcasted price update for zone {} to {} subscribers", zoneId, subscribers.size());
            }

            // Broadcast to all-zones subscribers
            if (!allZonesSubscribers.isEmpty()) {
                try {
                    String allZonesData = objectMapper.writeValueAsString(java.util.Map.of(
                            "zone_id", zoneId,
                            "surge_multiplier", response.getSurgeMultiplier(),
                            "demand", response.getDemand(),
                            "supply", response.getSupply(),
                            "ratio", response.getRatio(),
                            "updated_at", response.getUpdatedAt()
                    ));
                    
                    for (SseEmitter emitter : new CopyOnWriteArrayList<>(allZonesSubscribers)) {
                        try {
                            emitter.send(SseEmitter.event()
                                    .name("zone-update")
                                    .data(allZonesData));
                        } catch (IOException e) {
                            logger.warn("Failed to send update to all-zones subscriber: {}", e.getMessage());
                            allZonesSubscribers.remove(emitter);
                        }
                    }
                } catch (Exception e) {
                    logger.error("Error broadcasting to all-zones subscribers: {}", e.getMessage());
                }
            }

        } catch (Exception e) {
            logger.error("Error broadcasting price update for zone {}: {}", zoneId, e.getMessage());
        }
    }

    private void removeSubscription(Integer zoneId, SseEmitter emitter) {
        CopyOnWriteArrayList<SseEmitter> subscribers = zoneSubscriptions.get(zoneId);
        if (subscribers != null) {
            subscribers.remove(emitter);
            if (subscribers.isEmpty()) {
                zoneSubscriptions.remove(zoneId);
            }
            logger.debug("Removed SSE subscription for zone {}. Remaining: {}", zoneId, subscribers.size());
        }
    }

    public int getSubscriberCount(Integer zoneId) {
        return zoneSubscriptions.getOrDefault(zoneId, new CopyOnWriteArrayList<>()).size();
    }

    public int getTotalSubscribers() {
        return zoneSubscriptions.values().stream()
                .mapToInt(CopyOnWriteArrayList::size)
                .sum() + allZonesSubscribers.size();
    }

    public SseEmitter subscribeToAllZones() {
        logger.info("Creating SSE emitter for all zones");
        SseEmitter emitter = new SseEmitter(TIMEOUT);
        
        allZonesSubscribers.add(emitter);
        
        emitter.onCompletion(() -> {
            logger.debug("All-zones SSE emitter completed");
            allZonesSubscribers.remove(emitter);
        });
        
        emitter.onTimeout(() -> {
            logger.warn("All-zones SSE emitter timeout");
            allZonesSubscribers.remove(emitter);
        });
        
        emitter.onError(throwable -> {
            logger.warn("All-zones SSE error: {}", throwable.getMessage());
            allZonesSubscribers.remove(emitter);
        });

        try {
            emitter.send(SseEmitter.event()
                    .name("connected")
                    .data("{\"message\":\"Connected to all zones stream\"}"));
            logger.info("All-zones SSE subscription created. Total subscribers: {}", allZonesSubscribers.size());
        } catch (IOException e) {
            logger.error("Error sending initial SSE event for all zones: {}", e.getMessage());
            allZonesSubscribers.remove(emitter);
        }

        return emitter;
    }

    /**
     * Send periodic heartbeat comments to keep SSE connections alive
     * Runs every 10 seconds - more frequent to prevent timeouts
     */
    @Scheduled(fixedDelay = 10000)
    public void sendHeartbeat() {
        int totalHeartbeats = 0;
        int failedHeartbeats = 0;

        // Heartbeat for zone-specific subscribers
        for (Map.Entry<Integer, CopyOnWriteArrayList<SseEmitter>> entry : zoneSubscriptions.entrySet()) {
            Integer zoneId = entry.getKey();
            CopyOnWriteArrayList<SseEmitter> subscribers = entry.getValue();

            for (SseEmitter emitter : new CopyOnWriteArrayList<>(subscribers)) {
                try {
                    emitter.send(SseEmitter.event().comment("heartbeat"));
                    totalHeartbeats++;
                } catch (IOException e) {
                    logger.debug("Heartbeat failed for zone {}, removing dead connection: {}", zoneId, e.getMessage());
                    removeSubscription(zoneId, emitter);
                    failedHeartbeats++;
                }
            }
        }

        // Heartbeat for all-zones subscribers
        for (SseEmitter emitter : new CopyOnWriteArrayList<>(allZonesSubscribers)) {
            try {
                emitter.send(SseEmitter.event().comment("heartbeat"));
                totalHeartbeats++;
            } catch (IOException e) {
                logger.debug("Heartbeat failed for all-zones subscriber: {}", e.getMessage());
                allZonesSubscribers.remove(emitter);
                failedHeartbeats++;
            }
        }

        if (totalHeartbeats > 0) {
            logger.debug("Sent {} heartbeats ({} failed)", totalHeartbeats, failedHeartbeats);
        }
    }
}
