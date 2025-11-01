package com.pricing.api.service;

import com.pricing.api.dto.QuoteRequest;
import com.pricing.api.dto.ZoneHistoryResponse;
import com.pricing.api.dto.ZonePriceResponse;
import com.pricing.api.entity.FareConfig;
import com.pricing.api.entity.ZonePriceSnapshot;
import com.pricing.api.entity.ZoneWindowMetrics;
import com.pricing.api.repository.FareConfigRepository;
import com.pricing.api.repository.ZonePriceSnapshotRepository;
import com.pricing.api.repository.ZoneWindowMetricsRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;

@Service
public class PricingService {

    private static final Logger logger = LoggerFactory.getLogger(PricingService.class);

    // Cache for zone-based default estimates
    private static final Map<String, Double> DEFAULT_TRIP_ESTIMATES = Map.of(
        "DOWNTOWN", 4.2,    // Average 4.2km, 12min in dense downtown
        "URBAN", 6.8,       // Average 6.8km, 15min in urban areas  
        "SUBURBAN", 8.5,    // Average 8.5km, 18min in suburbs
        "AIRPORT", 12.0     // Average 12km, 25min airport trips
    );

    private static final Map<String, Double> DEFAULT_TIME_ESTIMATES = Map.of(
        "DOWNTOWN", 12.0,   // Higher time due to traffic
        "URBAN", 15.0,      
        "SUBURBAN", 18.0,   // Lower traffic, longer distances
        "AIRPORT", 25.0     // Highway + airport access time
    );

    private final ZonePriceSnapshotRepository snapshotRepository;
    private final FareConfigRepository fareConfigRepository;
    private final ZoneWindowMetricsRepository metricsRepository;
    
    // Cache for fare configs to avoid repeated DB calls
    private final Map<Integer, FareConfig> fareConfigCache = new ConcurrentHashMap<>();

    public PricingService(ZonePriceSnapshotRepository snapshotRepository, 
                         FareConfigRepository fareConfigRepository,
                          ZoneWindowMetricsRepository metricsRepository) {
        this.snapshotRepository = snapshotRepository;
        this.fareConfigRepository = fareConfigRepository;
        this.metricsRepository = metricsRepository;
        loadFareConfigCache();
    }

    public ZonePriceResponse getZonePrice(Integer zoneId) {
        logger.debug("Getting price for zone {}", zoneId);

        Optional<ZonePriceSnapshot> snapshot = snapshotRepository.findById(zoneId);
        if (snapshot.isEmpty()) {
            logger.warn("No price snapshot found for zone {}, using default surge multiplier", zoneId);
            return new ZonePriceResponse(zoneId, BigDecimal.ONE, null, OffsetDateTime.now(), 0, 0, BigDecimal.ZERO);
        }

        ZonePriceSnapshot priceSnapshot = snapshot.get();

        BigDecimal referenceFare = calculateReferenceFare(zoneId, null, null);
        BigDecimal quotedFare = referenceFare != null ?
                referenceFare.multiply(priceSnapshot.getSurgeMultiplier()).setScale(2, RoundingMode.HALF_UP) :
                null;

        return new ZonePriceResponse(
                zoneId,
                priceSnapshot.getSurgeMultiplier(),
                quotedFare,
                priceSnapshot.getUpdatedAt(),
                priceSnapshot.getDemand(),
                priceSnapshot.getSupply(),
                priceSnapshot.getRatio());
    }

    public ZonePriceResponse calculateQuote(QuoteRequest request) {
        logger.debug("Calculating quote for request: origin={}, destination={}, distance={}, duration={}",
                request.getOriginZoneId(), request.getDestinationZoneId(),
                request.getEstimatedDistanceKm(), request.getEstimatedDurationMin());

        Integer zoneId = request.getOriginZoneId();

        Optional<ZonePriceSnapshot> snapshot = snapshotRepository.findById(zoneId);
        BigDecimal surgeMultiplier = snapshot.map(ZonePriceSnapshot::getSurgeMultiplier).orElse(BigDecimal.ONE);
        Integer demand = snapshot.map(ZonePriceSnapshot::getDemand).orElse(0);
        Integer supply = snapshot.map(ZonePriceSnapshot::getSupply).orElse(0);
        BigDecimal ratio = snapshot.map(ZonePriceSnapshot::getRatio).orElse(BigDecimal.ZERO);

        BigDecimal baseFare = calculateReferenceFare(zoneId, request.getEstimatedDistanceKm(), request.getEstimatedDurationMin());
        BigDecimal quotedFare = baseFare != null ?
                baseFare.multiply(surgeMultiplier).setScale(2, RoundingMode.HALF_UP) : null;

        return new ZonePriceResponse(
                zoneId,
                surgeMultiplier,
                quotedFare,
                OffsetDateTime.now(),
                demand,
                supply,
                ratio);
    }

    public ZoneHistoryResponse getZoneHistory(Integer zoneId, Long fromTimestamp, Long toTimestamp) {
        logger.debug("Getting history for zone {} from {} to {}", zoneId, fromTimestamp, toTimestamp);

        OffsetDateTime to = toTimestamp != null ?
                OffsetDateTime.ofInstant(Instant.ofEpochMilli(toTimestamp), ZoneOffset.UTC) :
                OffsetDateTime.now();

        OffsetDateTime from = fromTimestamp != null ?
                OffsetDateTime.ofInstant(Instant.ofEpochMilli(fromTimestamp), ZoneOffset.UTC) :
                to.minusHours(24);

        List<ZoneWindowMetrics> metrics;

        if (fromTimestamp != null || toTimestamp != null) {
            metrics = metricsRepository.findByZoneIdAndTimeRange(zoneId, from, to);
        } else {
            Pageable pageable = PageRequest.of(0, 100);
            metrics = metricsRepository.findRecentByZoneId(zoneId, pageable);
            if (!metrics.isEmpty()) {
                from = metrics.get(metrics.size() - 1).getWindowStart();
                to = metrics.get(0).getWindowEnd();
            }
        }

        List<ZoneHistoryResponse.WindowMetric> windowMetrics = metrics.stream()
                .map(m -> new ZoneHistoryResponse.WindowMetric(
                        m.getWindowStart(),
                        m.getWindowEnd(),
                        m.getDemand(),
                        m.getSupply(),
                        m.getRatio(),
                        m.getSurgeMultiplier(),
                        m.getTsCompute()
                ))
                .collect(Collectors.toList());

        return new ZoneHistoryResponse(zoneId, from, to, windowMetrics);
    }

    public List<ZoneWindowMetrics> getRecentAuditRecords(int limit) {
        logger.debug("Getting recent audit records, limit: {}", limit);
        Pageable pageable = PageRequest.of(0, limit);
        return metricsRepository.findRecentAllZones(pageable);
    }

    private BigDecimal calculateReferenceFare(Integer zoneId, Double distanceKm, Double durationMin) {
        FareConfig config = getFareConfig(zoneId);
        
        if (config == null) {
            logger.warn("No fare config found for zone {}, using fallback", zoneId);
            return getZoneFallbackFare(zoneId);
        }

        BigDecimal fare = config.getBaseFare();
        String zoneType = config.getZoneType();

        // Use provided estimates or smart defaults based on zone type
        double effectiveDistance = distanceKm != null ? distanceKm : 
            DEFAULT_TRIP_ESTIMATES.getOrDefault(zoneType, 6.0);
            
        double effectiveDuration = durationMin != null ? durationMin : 
            DEFAULT_TIME_ESTIMATES.getOrDefault(zoneType, 15.0);

        // Calculate fare components
        BigDecimal distanceFare = config.getDistanceRate()
            .multiply(BigDecimal.valueOf(effectiveDistance));
            
        BigDecimal timeFare = config.getTimeRate()
            .multiply(BigDecimal.valueOf(effectiveDuration));

        fare = fare.add(distanceFare).add(timeFare);

        // Apply minimum fare
        if (fare.compareTo(config.getMinimumFare()) < 0) {
            fare = config.getMinimumFare();
        }

        logger.debug("Calculated fare for zone {} ({}): base={}, distance={}km*{}, time={}min*{}, total={}",
            zoneId, zoneType, config.getBaseFare(), effectiveDistance, config.getDistanceRate(),
            effectiveDuration, config.getTimeRate(), fare);

        return fare.setScale(2, RoundingMode.HALF_UP);
    }

    private FareConfig getFareConfig(Integer zoneId) {
        return fareConfigCache.computeIfAbsent(zoneId, id -> {
            Optional<FareConfig> config = fareConfigRepository.findById(id);
            return config.orElse(null);
        });
    }

    private void loadFareConfigCache() {
        try {
            List<FareConfig> allConfigs = fareConfigRepository.findAll();
            allConfigs.forEach(config -> 
                fareConfigCache.put(config.getZoneId(), config));
            logger.info("Loaded {} fare configurations into cache", allConfigs.size());
        } catch (Exception e) {
            logger.warn("Failed to load fare config cache: {}", e.getMessage());
        }
    }

    private BigDecimal getZoneFallbackFare(Integer zoneId) {
        // Simple zone-based fallback logic
        if (zoneId <= 16) {
            return new BigDecimal("22.50"); // Downtown estimate
        } else if (zoneId <= 32) {
            return new BigDecimal("16.80"); // Urban estimate  
        } else if (zoneId <= 48) {
            return new BigDecimal("12.30"); // Suburban estimate
        } else {
            return new BigDecimal("35.00"); // Airport estimate
        }
    }
}
