package com.pricing.api.controller;

import com.pricing.api.dto.QuoteRequest;
import com.pricing.api.dto.ZoneHistoryResponse;
import com.pricing.api.dto.ZonePriceResponse;
import com.pricing.api.service.PricingService;
import com.pricing.api.service.StreamingService;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

@RestController
@RequestMapping("/api/v1")
public class PricingController {

    private static final Logger logger = LoggerFactory.getLogger(PricingController.class);
    private static final Integer MIN_ZONES = 1;
    private static final Integer MAX_ZONES = 16;

    private final PricingService pricingService;
    private final StreamingService streamingService;

    public PricingController(PricingService pricingService, StreamingService streamingService) {
        this.pricingService = pricingService;
        this.streamingService = streamingService;
    }

    @GetMapping("/zones/{zoneId}/price")
    public ResponseEntity<ZonePriceResponse> getZonePrice(@PathVariable Integer zoneId) {
        logger.info("GET /zones/{}/price", zoneId);

        if (zoneId < MIN_ZONES || zoneId > MAX_ZONES) {
            return ResponseEntity.badRequest().build();
        }

        ZonePriceResponse response = pricingService.getZonePrice(zoneId);
        return ResponseEntity.ok(response);
    }

    @PostMapping("/quote")
    public ResponseEntity<ZonePriceResponse> calculateQuote(@Valid @RequestBody QuoteRequest request) {
        logger.info("POST /quote for origin zone {}", request.getOriginZoneId());

        ZonePriceResponse response = pricingService.calculateQuote(request);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/zones/{zoneId}/history")
    public ResponseEntity<?> getZoneHistory(
            @PathVariable Integer zoneId,
            @RequestParam(required = false) Long from,
            @RequestParam(required = false) Long to) {
        logger.info("GET /zones/{}/history?from={}&to={}", zoneId, from, to);

        if (zoneId < MIN_ZONES || zoneId > MAX_ZONES) {
            return ResponseEntity.badRequest().build();
        }

        try {
            ZoneHistoryResponse history = pricingService.getZoneHistory(zoneId, from, to);
            return ResponseEntity.ok(history);
        } catch (Exception e) {
            logger.error("Error getting history for zone {}: {}", zoneId, e.getMessage());
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping(value = "/zones/{zoneId}/stream", produces = "text/event-stream")
    public ResponseEntity<SseEmitter> streamZonePrices(@PathVariable Integer zoneId) {
        logger.info("GET /zones/{}/stream", zoneId);

        if (zoneId < MIN_ZONES || zoneId > MAX_ZONES) {
            return ResponseEntity.badRequest().build();
        }

        try {
            SseEmitter emitter = streamingService.subscribeToZone(zoneId);
            return ResponseEntity.ok(emitter);
        } catch (Exception e) {
            logger.error("Error creating SSE stream for zone {}: {}", zoneId, e.getMessage());
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping(value = "/zones/all/stream", produces = "text/event-stream")
    public ResponseEntity<SseEmitter> streamAllZones() {
        logger.info("GET /zones/all/stream");

        try {
            SseEmitter emitter = streamingService.subscribeToAllZones();
            return ResponseEntity.ok(emitter);
        } catch (Exception e) {
            logger.error("Error creating SSE stream for all zones: {}", e.getMessage());
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/health")
    public ResponseEntity<Object> healthCheck() {
        return ResponseEntity.ok(java.util.Map.of(
                "status", "UP",
                "service", "pricing-api",
                "timestamp", java.time.OffsetDateTime.now(),
                "active_sse_connections", streamingService.getTotalSubscribers()
        ));
    }
}
