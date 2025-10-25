package com.pricing.api.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "zone_price_snapshot")
public class ZonePriceSnapshot {

    @Id
    @Column(name = "zone_id")
    private Integer zoneId;

    @Column(name = "surge_multiplier", precision = 4, scale = 2, nullable = false)
    private BigDecimal surgeMultiplier = BigDecimal.ONE;

    @Column(name = "demand", nullable = false)
    private Integer demand = 0;

    @Column(name = "supply", nullable = false)
    private Integer supply = 0;

    @Column(name = "ratio", precision = 10, scale = 4, nullable = false)
    private BigDecimal ratio = BigDecimal.ZERO;

    @Column(name = "window_start", nullable = false)
    private OffsetDateTime windowStart;

    @Column(name = "window_end", nullable = false)
    private OffsetDateTime windowEnd;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    public ZonePriceSnapshot() {}

    public Integer getZoneId() {
        return zoneId;
    }

    public void setZoneId(Integer zoneId) {
        this.zoneId = zoneId;
    }

    public BigDecimal getSurgeMultiplier() {
        return surgeMultiplier;
    }

    public void setSurgeMultiplier(BigDecimal surgeMultiplier) {
        this.surgeMultiplier = surgeMultiplier;
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

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(OffsetDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }
}
