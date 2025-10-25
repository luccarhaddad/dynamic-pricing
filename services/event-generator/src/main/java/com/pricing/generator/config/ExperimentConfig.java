package com.pricing.generator.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "experiment")
public class ExperimentConfig {

    private boolean deterministic = true;
    private long seed = 12345L;
    private String scenario = "normal"; // normal, network-delay, dropped-events, burst-traffic
    private double failureRate = 0.0; // 0.0 = no failures, 1.0 = all events fail
    private int networkDelayMs = 0; // Artificial network delay
    private double burstMultiplier = 1.0; // Multiplier for burst scenarios

    public boolean isDeterministic() {
        return deterministic;
    }

    public void setDeterministic(boolean deterministic) {
        this.deterministic = deterministic;
    }

    public long getSeed() {
        return seed;
    }

    public void setSeed(long seed) {
        this.seed = seed;
    }

    public String getScenario() {
        return scenario;
    }

    public void setScenario(String scenario) {
        this.scenario = scenario;
    }

    public double getFailureRate() {
        return failureRate;
    }

    public void setFailureRate(double failureRate) {
        this.failureRate = failureRate;
    }

    public int getNetworkDelayMs() {
        return networkDelayMs;
    }

    public void setNetworkDelayMs(int networkDelayMs) {
        this.networkDelayMs = networkDelayMs;
    }

    public double getBurstMultiplier() {
        return burstMultiplier;
    }

    public void setBurstMultiplier(double burstMultiplier) {
        this.burstMultiplier = burstMultiplier;
    }
}
