package com.pricing.generator.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app")
public class AppProperties {

    private int zones = 16;
    private long heartbeatIntervalMs = 4000;
    private double ridesLambda = 0.6;
    private int driversPerZone = 15;

    public int getZones() {
        return zones;
    }

    public void setZones(int zones) {
        this.zones = zones;
    }

    public long getHeartbeatIntervalMs() {
        return heartbeatIntervalMs;
    }

    public void setHeartbeatIntervalMs(long heartbeatIntervalMs) {
        this.heartbeatIntervalMs = heartbeatIntervalMs;
    }

    public double getRidesLambda() {
        return ridesLambda;
    }

    public void setRidesLambda(double ridesLambda) {
        this.ridesLambda = ridesLambda;
    }

    public int getDriversPerZone() {
        return driversPerZone;
    }

    public void setDriversPerZone(int driversPerZone) {
        this.driversPerZone = driversPerZone;
    }
}