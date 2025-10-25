package com.pricing.api.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "fare_config")
public class FareConfig {

    @Id
    @Column(name = "zone_id")
    private Integer zoneId;

    @Column(name = "base_fare", precision = 8, scale = 2, nullable = false)
    private BigDecimal baseFare;

    @Column(name = "distance_rate", precision = 6, scale = 2, nullable = false)
    private BigDecimal distanceRate;

    @Column(name = "time_rate", precision = 6, scale = 2, nullable = false)
    private BigDecimal timeRate;

    @Column(name = "minimum_fare", precision = 8, scale = 2, nullable = false)
    private BigDecimal minimumFare;

    @Column(name = "zone_type", length = 20, nullable = false)
    private String zoneType = "STANDARD";

    @Column(name = "active", nullable = false)
    private Boolean active = true;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    public FareConfig() {}

    public Integer getZoneId() {
        return zoneId;
    }

    public void setZoneId(Integer zoneId) {
        this.zoneId = zoneId;
    }

    public BigDecimal getBaseFare() {
        return baseFare;
    }

    public void setBaseFare(BigDecimal baseFare) {
        this.baseFare = baseFare;
    }

    public BigDecimal getDistanceRate() {
        return distanceRate;
    }

    public void setDistanceRate(BigDecimal distanceRate) {
        this.distanceRate = distanceRate;
    }

    public BigDecimal getTimeRate() {
        return timeRate;
    }

    public void setTimeRate(BigDecimal timeRate) {
        this.timeRate = timeRate;
    }

    public BigDecimal getMinimumFare() {
        return minimumFare;
    }

    public void setMinimumFare(BigDecimal minimumFare) {
        this.minimumFare = minimumFare;
    }

    public Boolean getActive() {
        return active;
    }

    public void setActive(Boolean active) {
        this.active = active;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(OffsetDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(OffsetDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public String getZoneType() {
        return zoneType;
    }

    public void setZoneType(String zoneType) {
        this.zoneType = zoneType;
    }
}