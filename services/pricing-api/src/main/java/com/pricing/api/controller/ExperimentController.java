package com.pricing.api.controller;

import com.pricing.api.entity.ZonePriceSnapshot;
import com.pricing.api.repository.ZonePriceSnapshotRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.*;

@RestController
@RequestMapping("/api/v1/experiment")
public class ExperimentController {

    private static final Logger logger = LoggerFactory.getLogger(ExperimentController.class);
    private final ZonePriceSnapshotRepository snapshotRepository;

    public ExperimentController(ZonePriceSnapshotRepository snapshotRepository) {
        this.snapshotRepository = snapshotRepository;
    }

    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> getExperimentStatus() {
        logger.info("GET /experiment/status");

        Map<String, Object> status = new HashMap<>();
        
        // Get configuration from environment variables
        status.put("deterministic", System.getenv().getOrDefault("DETERMINISTIC", "true"));
        status.put("seed", System.getenv().getOrDefault("EXPERIMENT_SEED", "12345"));
        status.put("scenario", System.getenv().getOrDefault("SCENARIO", "baseline"));
        status.put("failureRate", System.getenv().getOrDefault("FAILURE_RATE", "0.0"));
        status.put("networkDelayMs", System.getenv().getOrDefault("NETWORK_DELAY_MS", "0"));
        status.put("burstMultiplier", System.getenv().getOrDefault("BURST_MULTIPLIER", "1.0"));
        
        return ResponseEntity.ok(status);
    }

    @GetMapping("/metrics")
    public ResponseEntity<Map<String, Object>> getExperimentMetrics() {
        logger.info("GET /experiment/metrics");

        Map<String, Object> metrics = new HashMap<>();
        
        // Get all zone snapshots
        List<ZonePriceSnapshot> snapshots = snapshotRepository.findAll();
        
        if (snapshots.isEmpty()) {
            metrics.put("message", "No data available yet");
            return ResponseEntity.ok(metrics);
        }
        
        // Calculate statistics
        double totalSurge = 0;
        double minSurge = Double.MAX_VALUE;
        double maxSurge = Double.MIN_VALUE;
        int totalDemand = 0;
        int totalSupply = 0;
        Set<Integer> activeZones = new HashSet<>();
        
        for (ZonePriceSnapshot snapshot : snapshots) {
            double surge = snapshot.getSurgeMultiplier().doubleValue();
            totalSurge += surge;
            minSurge = Math.min(minSurge, surge);
            maxSurge = Math.max(maxSurge, surge);
            totalDemand += snapshot.getDemand();
            totalSupply += snapshot.getSupply();
            activeZones.add(snapshot.getZoneId());
        }
        
        double avgSurge = totalSurge / snapshots.size();
        
        metrics.put("activeZones", activeZones.size());
        metrics.put("totalSnapshots", snapshots.size());
        metrics.put("averageSurge", avgSurge);
        metrics.put("minSurge", minSurge == Double.MAX_VALUE ? 0 : minSurge);
        metrics.put("maxSurge", maxSurge == Double.MIN_VALUE ? 0 : maxSurge);
        metrics.put("totalDemand", totalDemand);
        metrics.put("totalSupply", totalSupply);
        metrics.put("averageRatio", totalSupply > 0 ? (double) totalDemand / totalSupply : 0.0);
        
        // Zone distribution
        Map<String, Integer> surgeDistribution = new HashMap<>();
        surgeDistribution.put("normal", 0);    // 1.0x
        surgeDistribution.put("low", 0);      // 1.0x - 1.5x
        surgeDistribution.put("medium", 0);   // 1.5x - 2.0x
        surgeDistribution.put("high", 0);     // 2.0x - 2.5x
        surgeDistribution.put("extreme", 0);   // > 2.5x
        
        for (ZonePriceSnapshot snapshot : snapshots) {
            double surge = snapshot.getSurgeMultiplier().doubleValue();
            if (surge == 1.0) {
                surgeDistribution.put("normal", surgeDistribution.get("normal") + 1);
            } else if (surge < 1.5) {
                surgeDistribution.put("low", surgeDistribution.get("low") + 1);
            } else if (surge < 2.0) {
                surgeDistribution.put("medium", surgeDistribution.get("medium") + 1);
            } else if (surge < 2.5) {
                surgeDistribution.put("high", surgeDistribution.get("high") + 1);
            } else {
                surgeDistribution.put("extreme", surgeDistribution.get("extreme") + 1);
            }
        }
        
        metrics.put("surgeDistribution", surgeDistribution);
        
        return ResponseEntity.ok(metrics);
    }

    @GetMapping("/zones")
    public ResponseEntity<Map<String, Object>> getAllZonesData() {
        logger.info("GET /experiment/zones");

        Map<String, Object> result = new HashMap<>();
        List<Map<String, Object>> zones = new ArrayList<>();
        
        // Get all zone snapshots
        List<ZonePriceSnapshot> snapshots = snapshotRepository.findAll();
        
        for (ZonePriceSnapshot snapshot : snapshots) {
            Map<String, Object> zoneData = new HashMap<>();
            zoneData.put("zoneId", snapshot.getZoneId());
            zoneData.put("surgeMultiplier", snapshot.getSurgeMultiplier());
            zoneData.put("demand", snapshot.getDemand());
            zoneData.put("supply", snapshot.getSupply());
            zoneData.put("ratio", snapshot.getRatio());
            zoneData.put("updatedAt", snapshot.getUpdatedAt());
            zones.add(zoneData);
        }
        
        result.put("zones", zones);
        result.put("count", zones.size());
        
        return ResponseEntity.ok(result);
    }
}

