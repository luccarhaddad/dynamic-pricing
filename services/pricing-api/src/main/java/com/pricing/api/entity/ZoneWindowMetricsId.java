package com.pricing.api.entity;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.Objects;

public class ZoneWindowMetricsId implements Serializable {

    private Integer zoneId;
    private OffsetDateTime windowStart;

    public ZoneWindowMetricsId() {}

    public ZoneWindowMetricsId(Integer zoneId, OffsetDateTime windowStart) {
        this.zoneId = zoneId;
        this.windowStart = windowStart;
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

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        ZoneWindowMetricsId that = (ZoneWindowMetricsId) o;
        return Objects.equals(zoneId, that.zoneId) && Objects.equals(windowStart, that.windowStart);
    }

    @Override
    public int hashCode() {
        return Objects.hash(zoneId, windowStart);
    }
}