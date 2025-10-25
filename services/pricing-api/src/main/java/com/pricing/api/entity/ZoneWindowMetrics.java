package com.pricing.api.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "zone_window_metrics")
@IdClass(ZoneWindowMetricsId.class)
public class ZoneWindowMetrics {

    @Id
    @Column(name = "zone_id")
    private Integer zoneId;

    @Id
    @Column(name = "window_start")
    private OffsetDateTime windowStart;

    @Column(name = "window_end", nullable = false)
    private OffsetDateTime windowEnd;

    @Column(name = "demand", nullable = false)
    private Integer demand = 0;

    @Column(name = "supply", nullable = false)
    private Integer supply = 0;

    @Column(name = "ratio", precision = 10, scale = 4, nullable = false)
    private BigDecimal ratio = BigDecimal.ZERO;

    @Column(name = "surge_multiplier", precision = 4, scale = 2, nullable = false)
    private BigDecimal surgeMultiplier = BigDecimal.ONE;

    @Column(name = "ts_compute", nullable = false)
    private OffsetDateTime tsCompute = OffsetDateTime.now();

    public ZoneWindowMetrics() {}

    public ZoneWindowMetrics(Integer zoneId, OffsetDateTime windowStart, OffsetDateTime windowEnd,
                             Integer demand, Integer supply, BigDecimal ratio, BigDecimal surgeMultiplier) {
        this.zoneId = zoneId;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd;
        this.demand = demand;
        this.supply = supply;
        this.ratio = ratio;
        this.surgeMultiplier = surgeMultiplier;
        this.tsCompute = OffsetDateTime.now();
    }

    public Integer getZoneId() {
        return zoneId;
    }

    public void setZoneId(Integer zoneId) {
        this.zoneId = zoneId;
    }

    public OffsetDateTime getWindowStart() {
        return windowStart;
    }

    public void setWindowStart(OffsetDateTime windowStart) {
        this.windowStart = windowStart;
    }

    public OffsetDateTime getWindowEnd() {
        return windowEnd;
    }

    public void setWindowEnd(OffsetDateTime windowEnd) {
        this.windowEnd = windowEnd;
    }

    public Integer getDemand() {
        return demand;
    }

    public void setDemand(Integer demand) {
        this.demand = demand;
    }

    public Integer getSupply() {
        return supply;
    }

    public void setSupply(Integer supply) {
        this.supply = supply;
    }

    public BigDecimal getRatio() {
        return ratio;
    }

    public void setRatio(BigDecimal ratio) {
        this.ratio = ratio;
    }

    public BigDecimal getSurgeMultiplier() {
        return surgeMultiplier;
    }

    public void setSurgeMultiplier(BigDecimal surgeMultiplier) {
        this.surgeMultiplier = surgeMultiplier;
    }

    public OffsetDateTime getTsCompute() {
        return tsCompute;
    }

    public void setTsCompute(OffsetDateTime tsCompute) {
        this.tsCompute = tsCompute;
    }
}