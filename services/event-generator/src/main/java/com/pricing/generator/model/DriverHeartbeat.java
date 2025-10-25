package com.pricing.generator.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.pricing.generator.service.DeterministicRandom;

public class DriverHeartbeat {

    @JsonProperty("driver_id")
    private String driverId;

    @JsonProperty("zone_id")
    private int zoneId;

    @JsonProperty("status")
    private String status;

    @JsonProperty("ts_event")
    private long tsEvent;

    public DriverHeartbeat() {}

    public DriverHeartbeat(String driverId, int zoneId, String status, long tsEvent) {
        this.driverId = driverId;
        this.zoneId = zoneId;
        this.status = status;
        this.tsEvent = tsEvent;
    }

    public static DriverHeartbeat create(String driverId, int zoneId) {
        return create(driverId, zoneId, 0, false, 0L);
    }

    public static DriverHeartbeat create(String driverId, int zoneId, int heartbeatIndex, boolean deterministic, long seed) {
        DeterministicRandom rand = new DeterministicRandom(seed, deterministic);
        
        return new DriverHeartbeat(
                driverId,
                zoneId,
                rand.nextDouble() < 0.5 ? "AVAILABLE" : "BUSY", // 50% available
                deterministic ? seed + heartbeatIndex * 100 : System.currentTimeMillis()
        );
    }

    public String getDriverId() {
        return driverId;
    }

    public void setDriverId(String driverId) {
        this.driverId = driverId;
    }

    public int getZoneId() {
        return zoneId;
    }

    public void setZoneId(int zoneId) {
        this.zoneId = zoneId;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public long getTsEvent() {
        return tsEvent;
    }

    public void setTsEvent(long tsEvent) {
        this.tsEvent = tsEvent;
    }
}