package com.pricing.flink.model;

import com.fasterxml.jackson.annotation.JsonValue;

public enum HeartbeatStatus {
    AVAILABLE("AVAILABLE"),
    BUSY("BUSY");

    private final String value;

    HeartbeatStatus(String value) {
        this.value = value;
    }

    @JsonValue
    public String getValue() {
        return value;
    }

    public static HeartbeatStatus fromString(String text) {
        for (HeartbeatStatus status : HeartbeatStatus.values()) {
            if (status.value.equalsIgnoreCase(text)) {
                return status;
            }
        }
        throw new IllegalArgumentException("No enum constant for value: " + text);
    }

    @Override
    public String toString() {
        return value;
    }
}