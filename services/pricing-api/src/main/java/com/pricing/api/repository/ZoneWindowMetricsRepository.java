package com.pricing.api.repository;

import com.pricing.api.entity.ZoneWindowMetrics;
import com.pricing.api.entity.ZoneWindowMetricsId;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;

public interface ZoneWindowMetricsRepository extends JpaRepository<ZoneWindowMetrics, ZoneWindowMetricsId> {

    @Query("SELECT m FROM ZoneWindowMetrics m WHERE m.zoneId = :zoneId " +
            "AND m.windowStart >= :from AND m.windowEnd <= :to " +
            "ORDER BY m.windowStart DESC")
    List<ZoneWindowMetrics> findByZoneIdAndTimeRange(
            @Param("zoneId") Integer zoneId,
            @Param("from") OffsetDateTime from,
            @Param("to") OffsetDateTime to
    );

    @Query("SELECT m FROM ZoneWindowMetrics m WHERE m.zoneId = :zoneId " +
            "ORDER BY m.windowStart DESC")
    List<ZoneWindowMetrics> findByZoneIdOrderByWindowStartDesc(@Param("zoneId") Integer zoneId);

    @Query("SELECT m FROM ZoneWindowMetrics m WHERE m.zoneId = :zoneId " +
            "ORDER BY m.windowStart DESC")
    List<ZoneWindowMetrics> findRecentByZoneId(
            @Param("zoneId") Integer zoneId,
            Pageable pageable
    );

    @Query("SELECT m FROM ZoneWindowMetrics m ORDER BY m.tsCompute DESC")
    List<ZoneWindowMetrics> findRecentAllZones(Pageable pageable);
}
