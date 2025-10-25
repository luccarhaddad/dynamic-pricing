package com.pricing.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;

public class ZoneHistoryResponse {

    @JsonProperty("zone_id")
    private Integer zoneId;

    @JsonProperty("from")
    private OffsetDateTime from;

    @JsonProperty("to")
    private OffsetDateTime to;

    @JsonProperty("total_windows")
    private Integer totalWindows;

    @JsonProperty("metrics")
    private List<WindowMetric> metrics;

    public ZoneHistoryResponse() {}

    public ZoneHistoryResponse(Integer zoneId, OffsetDateTime from, OffsetDateTime to,
                               List<WindowMetric> metrics) {
        this.zoneId = zoneId;
        this.from = from;
        this.to = to;
        this.metrics = metrics;
        this.totalWindows = metrics.size();
    }

    public Integer getZoneId() {
        return zoneId;
    }

    public void setZoneId(Integer zoneId) {
        this.zoneId = zoneId;
    }

    public OffsetDateTime getFrom() {
        return from;
    }

    public void setFrom(OffsetDateTime from) {
        this.from = from;
    }

    public OffsetDateTime getTo() {
        return to;
    }

    public void setTo(OffsetDateTime to) {
        this.to = to;
    }

    public Integer getTotalWindows() {
        return totalWindows;
    }

    public void setTotalWindows(Integer totalWindows) {
        this.totalWindows = totalWindows;
    }

    public List<WindowMetric> getMetrics() {
        return metrics;
    }

    public void setMetrics(List<WindowMetric> metrics) {
        this.metrics = metrics;
    }

    public static class WindowMetric {

        @JsonProperty("window_start")
        private OffsetDateTime windowStart;

        @JsonProperty("window_end")
        private OffsetDateTime windowEnd;

        @JsonProperty("demand")
        private Integer demand;

        @JsonProperty("supply")
        private Integer supply;

        @JsonProperty("ratio")
        private BigDecimal ratio;

        @JsonProperty("surge_multiplier")
        private BigDecimal surgeMultiplier;

        @JsonProperty("computed_at")
        private OffsetDateTime computedAt;

        public WindowMetric() {}

        public WindowMetric(OffsetDateTime windowStart, OffsetDateTime windowEnd, Integer demand,
                            Integer supply, BigDecimal ratio, BigDecimal surgeMultiplier,
                            OffsetDateTime computedAt) {
            this.windowStart = windowStart;
            this.windowEnd = windowEnd;
            this.demand = demand;
            this.supply = supply;
            this.ratio = ratio;
            this.surgeMultiplier = surgeMultiplier;
            this.computedAt = computedAt;
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

        public OffsetDateTime getComputedAt() {
            return computedAt;
        }

        public void setComputedAt(OffsetDateTime computedAt) {
            this.computedAt = computedAt;
        }
    }
}