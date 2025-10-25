package com.pricing.flink.model;

public class NormalizedEvent {
    
    private String kind; // "RIDE" or "HEARTBEAT"
    private int zoneId;
    private long timestamp;
    private String status; // for heartbeats: AVAILABLE/BUSY, for rides: always null
    
    public NormalizedEvent() {}
    
    public NormalizedEvent(String kind, int zoneId, long timestamp, String status) {
        this.kind = kind;
        this.zoneId = zoneId;
        this.timestamp = timestamp;
        this.status = status;
    }
    
    // Factory methods
    public static NormalizedEvent forRide(int zoneId, long timestamp) {
        return new NormalizedEvent("RIDE", zoneId, timestamp, null);
    }
    
    public static NormalizedEvent forHeartbeat(int zoneId, long timestamp, String status) {
        return new NormalizedEvent("HEARTBEAT", zoneId, timestamp, status);
    }
    
    // Getters and setters
    public String getKind() {
        return kind;
    }
    
    public void setKind(String kind) {
        this.kind = kind;
    }
    
    public int getZoneId() {
        return zoneId;
    }
    
    public void setZoneId(int zoneId) {
        this.zoneId = zoneId;
    }
    
    public long getTimestamp() {
        return timestamp;
    }
    
    public void setTimestamp(long timestamp) {
        this.timestamp = timestamp;
    }
    
    public String getStatus() {
        return status;
    }
    
    public void setStatus(String status) {
        this.status = status;
    }
    
    @Override
    public String toString() {
        return String.format("NormalizedEvent{kind='%s', zoneId=%d, timestamp=%d, status='%s'}", 
            kind, zoneId, timestamp, status);
    }
}