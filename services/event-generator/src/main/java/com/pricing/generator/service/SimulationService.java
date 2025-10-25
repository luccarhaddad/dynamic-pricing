package com.pricing.generator.service;

import com.pricing.generator.config.AppProperties;
import com.pricing.generator.config.ExperimentConfig;
import com.pricing.generator.model.DriverHeartbeat;
import com.pricing.generator.model.RideRequest;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import jakarta.annotation.PostConstruct;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class SimulationService {
    private static final Logger logger = LoggerFactory.getLogger(SimulationService.class);

    private final AppProperties appProperties;
    private final ExperimentConfig experimentConfig;
    private final EventPublisher eventPublisher;
    private final Counter rideRequestCounter;
    private final Counter heartbeatCounter;
    private final Counter failedEventsCounter;

    private final Map<Integer, List<String>> driversByZone = new ConcurrentHashMap<>();
    private final Map<Integer, Long> nextRideTimeByZone = new ConcurrentHashMap<>();
    private final Map<Integer, AtomicInteger> rideRequestCounters = new ConcurrentHashMap<>();
    private final Map<Integer, AtomicInteger> heartbeatCounters = new ConcurrentHashMap<>();
    
    private final DeterministicRandom deterministicRandom;
    private final AtomicLong globalEventCounter = new AtomicLong(0);

    public SimulationService(AppProperties appProperties, ExperimentConfig experimentConfig, 
                           EventPublisher eventPublisher, MeterRegistry meterRegistry) {
        this.appProperties = appProperties;
        this.experimentConfig = experimentConfig;
        this.eventPublisher = eventPublisher;
        this.deterministicRandom = new DeterministicRandom(experimentConfig.getSeed(), experimentConfig.isDeterministic());
        
        this.rideRequestCounter = Counter.builder("ride_requests_published_total")
                .description("Total ride requests published")
                .register(meterRegistry);
        this.heartbeatCounter = Counter.builder("driver_heartbeats")
                .description("Total driver heartbeats published")
                .register(meterRegistry);
        this.failedEventsCounter = Counter.builder("failed_events_total")
                .description("Total failed events")
                .register(meterRegistry);
    }

    @PostConstruct
    public void initializeDrivers() {
        logger.info("Initializing simulation with {} zones, {} drivers per zone",
                appProperties.getZones(), appProperties.getDriversPerZone());
        logger.info("Experiment mode: deterministic={}, scenario={}, seed={}", 
                experimentConfig.isDeterministic(), experimentConfig.getScenario(), experimentConfig.getSeed());

        for (int zone = 1; zone <= appProperties.getZones(); zone++) {
            List<String> drivers = new ArrayList<>();
            for (int i = 0; i < appProperties.getDriversPerZone(); i++) {
                drivers.add(deterministicRandom.generateDeterministicUUID(zone * 1000 + i));
            }
            driversByZone.put(zone, drivers);
            rideRequestCounters.put(zone, new AtomicInteger(0));
            heartbeatCounters.put(zone, new AtomicInteger(0));

            nextRideTimeByZone.put(zone, calculateNextRideTime());
        }
        logger.info("Simulation initialized with {} total drivers across {} zones",
                appProperties.getZones() * appProperties.getDriversPerZone(), appProperties.getZones());
    }

    @Scheduled(fixedDelayString = "#{appProperties.heartbeatIntervalMs}")
    public void publishDriverHeartbeats() {
        long currentTime = System.currentTimeMillis();
        int totalHeartbeats = 0;
        int failedHeartbeats = 0;

        for (Map.Entry<Integer, List<String>> entry : driversByZone.entrySet()) {
            int zoneId = entry.getKey();
            List<String> drivers = entry.getValue();
            AtomicInteger zoneHeartbeatCounter = heartbeatCounters.get(zoneId);

            for (String driverId : drivers) {
                if (deterministicRandom.nextDouble() < 0.9) {
                    int heartbeatIndex = zoneHeartbeatCounter.incrementAndGet();
                    DriverHeartbeat heartbeat = DriverHeartbeat.create(
                        driverId, zoneId, heartbeatIndex, 
                        experimentConfig.isDeterministic(), experimentConfig.getSeed()
                    );
                    
                    if (shouldSimulateFailure()) {
                        failedHeartbeats++;
                        failedEventsCounter.increment();
                        logger.debug("Simulated failure for heartbeat: zone={}, driver={}", zoneId, driverId);
                    } else {
                        publishWithDelay(() -> eventPublisher.publishDriverHeartbeat(heartbeat));
                        heartbeatCounter.increment();
                        totalHeartbeats++;
                    }
                }
            }
        }

        logger.info("Published {} driver heartbeats ({} failed) at {}", totalHeartbeats, failedHeartbeats, currentTime);
    }

    @Scheduled(fixedDelay = 100)
    public void publishRideRequests() {
        long currentTime = System.currentTimeMillis();
        int totalRequests = 0;
        int failedRequests = 0;

        for (int zone = 1; zone <= appProperties.getZones(); zone++) {
            Long nextRideTime = nextRideTimeByZone.get(zone);
            if (nextRideTime != null && currentTime >= nextRideTime) {
                AtomicInteger zoneRequestCounter = rideRequestCounters.get(zone);
                int requestIndex = zoneRequestCounter.incrementAndGet();
                
                RideRequest request = RideRequest.create(
                    zone, requestIndex, 
                    experimentConfig.isDeterministic(), experimentConfig.getSeed()
                );
                
                if (shouldSimulateFailure()) {
                    failedRequests++;
                    failedEventsCounter.increment();
                    logger.debug("Simulated failure for ride request: zone={}, event={}", zone, request.getEventId());
                } else {
                    publishWithDelay(() -> eventPublisher.publishRideRequest(request));
                    rideRequestCounter.increment();
                    totalRequests++;
                }

                nextRideTimeByZone.put(zone, currentTime + calculateNextRideTime());
                logger.debug("Published ride request for zone {} at {}", zone, currentTime);
            }
        }
        
        if (totalRequests > 0 || failedRequests > 0) {
            logger.info("Published {} ride requests ({} failed) at {}", totalRequests, failedRequests, currentTime);
        }
    }

    private long calculateNextRideTime() {
        // Poisson process: inter-arrival time follows exponential distribution
        double lambda = appProperties.getRidesLambda() * experimentConfig.getBurstMultiplier();
        double intervalSeconds = deterministicRandom.nextExponential(lambda);
        return (long) (intervalSeconds * 1000);
    }
    
    private boolean shouldSimulateFailure() {
        if (experimentConfig.getFailureRate() <= 0.0) {
            return false;
        }
        return deterministicRandom.nextDouble() < experimentConfig.getFailureRate();
    }
    
    private void publishWithDelay(Runnable publishAction) {
        if (experimentConfig.getNetworkDelayMs() > 0) {
            try {
                Thread.sleep(experimentConfig.getNetworkDelayMs());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        publishAction.run();
    }
}
