package com.pricing.flink.model;

import com.fasterxml.jackson.annotation.JsonValue;

public enum EventKind {
    RIDE("RIDE"),
    HEARTBEAT("HEARTBEAT");

    private final String value;

    EventKind(String value) {
        this.value = value;
    }

    @JsonValue
    public String getValue() {
        return value;
    }

    public static EventKind fromString(String text) {
        for (EventKind kind : EventKind.values()) {
            if (kind.value.equalsIgnoreCase(text)) {
                return kind;
            }
        }
        throw new IllegalArgumentException("No enum constant for value: " + text);
    }

    @Override
    public String toString() {
        return value;
    }
}
