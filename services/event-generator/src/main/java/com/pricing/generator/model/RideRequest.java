package com.pricing.generator.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.pricing.generator.service.DeterministicRandom;

public class RideRequest {

    @JsonProperty("event_id")
    private String eventId;

    @JsonProperty("rider_id")
    private String riderId;

    @JsonProperty("zone_id")
    private int zoneId;

    @JsonProperty("est_distance_km")
    private double estDistanceKm;

    @JsonProperty("est_duration_min")
    private double estDurationMin;

    @JsonProperty("payment_type")
    private String paymentType;

    @JsonProperty("ts_event")
    private long tsEvent;

    public RideRequest() {}

    public RideRequest(String eventId, String riderId, int zoneId, double estDistanceKm,
                       double estDurationMin, String paymentType, long tsEvent) {
        this.eventId = eventId;
        this.riderId = riderId;
        this.zoneId = zoneId;
        this.estDistanceKm = estDistanceKm;
        this.estDurationMin = estDurationMin;
        this.paymentType = paymentType;
        this.tsEvent = tsEvent;
    }

    public static RideRequest create(int zoneId) {
        return create(zoneId, 0, false, 0L);
    }

    public static RideRequest create(int zoneId, int eventIndex, boolean deterministic, long seed) {
        DeterministicRandom rand = new DeterministicRandom(seed, deterministic);
        
        return new RideRequest(
                rand.generateDeterministicEventId(zoneId, eventIndex),
                rand.generateDeterministicRiderId(zoneId, eventIndex),
                zoneId,
                0.5 + rand.nextDouble() * 20.0, // 0.5-20.5 km
                3.0 + rand.nextDouble() * 35.0,  // 3-38 minutes
                getRandomPaymentType(rand),
                deterministic ? seed + eventIndex * 1000 : System.currentTimeMillis()
        );
    }

    private static String getRandomPaymentType(DeterministicRandom rand) {
        String[] types = {"CARD", "PIX", "CASH"};
        return types[rand.nextInt(types.length)];
    }

    public String getEventId() {
        return eventId;
    }

    public void setEventId(String eventId) {
        this.eventId = eventId;
    }

    public String getRiderId() {
        return riderId;
    }

    public void setRiderId(String riderId) {
        this.riderId = riderId;
    }

    public int getZoneId() {
        return zoneId;
    }

    public void setZoneId(int zoneId) {
        this.zoneId = zoneId;
    }

    public double getEstDistanceKm() {
        return estDistanceKm;
    }

    public void setEstDistanceKm(double estDistanceKm) {
        this.estDistanceKm = estDistanceKm;
    }

    public double getEstDurationMin() {
        return estDurationMin;
    }

    public void setEstDurationMin(double estDurationMin) {
        this.estDurationMin = estDurationMin;
    }

    public String getPaymentType() {
        return paymentType;
    }

    public void setPaymentType(String paymentType) {
        this.paymentType = paymentType;
    }

    public long getTsEvent() {
        return tsEvent;
    }

    public void setTsEvent(long tsEvent) {
        this.tsEvent = tsEvent;
    }
}