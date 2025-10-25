package com.pricing.flink.model;

import com.fasterxml.jackson.annotation.JsonProperty;

public class PriceUpdate {

    @JsonProperty("zone_id")
    private int zoneId;

    @JsonProperty("window_start")
    private long windowStart;

    @JsonProperty("window_end")
    private long windowEnd;

    @JsonProperty("demand")
    private int demand;

    @JsonProperty("supply")
    private int supply;

    @JsonProperty("ratio")
    private double ratio;

    @JsonProperty("surge_multiplier")
    private double surgeMultiplier;

    @JsonProperty("ts_compute")
    private long tsCompute;

    public PriceUpdate() {}

    public PriceUpdate(int zoneId, long windowStart, long windowEnd, int demand,
                       int supply, double ratio, double surgeMultiplier, long tsCompute) {
        this.zoneId = zoneId;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd;
        this.demand = demand;
        this.supply = supply;
        this.ratio = ratio;
        this.surgeMultiplier = surgeMultiplier;
        this.tsCompute = tsCompute;
    }

    // Getters and setters
    public int getZoneId() {
        return zoneId;
    }

    public void setZoneId(int zoneId) {
        this.zoneId = zoneId;
    }

    public long getWindowStart() {
        return windowStart;
    }

    public void setWindowStart(long windowStart) {
        this.windowStart = windowStart;
    }

    public long getWindowEnd() {
        return windowEnd;
    }

    public void setWindowEnd(long windowEnd) {
        this.windowEnd = windowEnd;
    }

    public int getDemand() {
        return demand;
    }

    public void setDemand(int demand) {
        this.demand = demand;
    }

    public int getSupply() {
        return supply;
    }

    public void setSupply(int supply) {
        this.supply = supply;
    }

    public double getRatio() {
        return ratio;
    }

    public void setRatio(double ratio) {
        this.ratio = ratio;
    }

    public double getSurgeMultiplier() {
        return surgeMultiplier;
    }

    public void setSurgeMultiplier(double surgeMultiplier) {
        this.surgeMultiplier = surgeMultiplier;
    }

    public long getTsCompute() {
        return tsCompute;
    }

    public void setTsCompute(long tsCompute) {
        this.tsCompute = tsCompute;
    }

    @Override
    public String toString() {
        return String.format("PriceUpdate{zoneId=%d, demand=%d, supply=%d, ratio=%.2f, surge=%.2f, ts=%d}",
                zoneId, demand, supply, ratio, surgeMultiplier, tsCompute);
    }
}