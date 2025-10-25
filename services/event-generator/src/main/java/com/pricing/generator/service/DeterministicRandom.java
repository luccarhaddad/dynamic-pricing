package com.pricing.generator.service;

import java.util.Random;

/**
 * Deterministic random number generator for reproducible experiments.
 * Uses a seeded Random instance to ensure consistent results across runs.
 */
public class DeterministicRandom {
    
    private final Random random;
    private final boolean deterministic;
    
    public DeterministicRandom(long seed, boolean deterministic) {
        this.random = new Random(seed);
        this.deterministic = deterministic;
    }
    
    public double nextDouble() {
        return deterministic ? random.nextDouble() : Math.random();
    }
    
    public int nextInt(int bound) {
        return deterministic ? random.nextInt(bound) : (int) (Math.random() * bound);
    }
    
    public boolean nextBoolean() {
        return deterministic ? random.nextBoolean() : Math.random() < 0.5;
    }
    
    public long nextLong() {
        return deterministic ? random.nextLong() : System.nanoTime();
    }
    
    public double nextGaussian() {
        return deterministic ? random.nextGaussian() : Math.random();
    }
    
    public double nextExponential(double lambda) {
        if (deterministic) {
            return -Math.log(1.0 - random.nextDouble()) / lambda;
        } else {
            return -Math.log(1.0 - Math.random()) / lambda;
        }
    }
    
    public String generateDeterministicUUID(int index) {
        if (deterministic) {
            // Generate deterministic UUID-like string based on index
            return String.format("driver-%08d-%04d-%04d-%04d-%012d", 
                index / 1000000, 
                (index / 10000) % 10000, 
                (index / 100) % 10000, 
                index % 10000, 
                index);
        } else {
            return java.util.UUID.randomUUID().toString();
        }
    }
    
    public String generateDeterministicRiderId(int zoneId, int eventIndex) {
        if (deterministic) {
            return String.format("rider-%02d-%06d", zoneId, eventIndex);
        } else {
            return java.util.UUID.randomUUID().toString();
        }
    }
    
    public String generateDeterministicEventId(int zoneId, int eventIndex) {
        if (deterministic) {
            return String.format("event-%02d-%06d", zoneId, eventIndex);
        } else {
            return java.util.UUID.randomUUID().toString();
        }
    }
}
