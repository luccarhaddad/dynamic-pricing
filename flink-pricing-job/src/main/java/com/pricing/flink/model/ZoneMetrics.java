package com.pricing.flink.model;

public class ZoneMetrics {

    private int zoneId;
    private long windowStart;
    private long windowEnd;
    private int demand;
    private int supply;
    private double ratio;

    public ZoneMetrics() {}

    public ZoneMetrics(int zoneId, long windowStart, long windowEnd, int demand, int supply) {
        this.zoneId = zoneId;
        this.windowStart = windowStart;
        this.windowEnd = windowEnd;
        this.demand = demand;
        this.supply = supply;
        // Cap ratio at 999.0 to prevent database overflow (DECIMAL(10,4) max ~999,999.9999)
        this.ratio = supply > 0 ? (double) demand / supply : demand > 0 ? 999.0 : 0.0;
    }

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

    @Override
    public String toString() {
        return String.format("ZoneMetrics{zoneId=%d, window=[%d,%d], demand=%d, supply=%d, ratio=%.2f}",
                zoneId, windowStart, windowEnd, demand, supply, ratio);
    }
}
