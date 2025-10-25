package com.pricing.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

public class QuoteRequest {

    @JsonProperty("origin_zone_id")
    @NotNull
    @Min(1)
    @Max(64)
    private Integer originZoneId;

    @JsonProperty("destination_zone_id")
    @NotNull
    @Min(1)
    @Max(64)
    private Integer destinationZoneId;

    @JsonProperty("estimated_distance_km")
    @Min(0)
    private Double estimatedDistanceKm;

    @JsonProperty("estimated_duration_min")
    @Min(0)
    private Double estimatedDurationMin;

    @JsonProperty("ts")
    private Long timestamp;

    public QuoteRequest() {}

    public Integer getOriginZoneId() {
        return originZoneId;
    }

    public void setOriginZoneId(Integer originZoneId) {
        this.originZoneId = originZoneId;
    }

    public Integer getDestinationZoneId() {
        return destinationZoneId;
    }

    public void setDestinationZoneId(Integer destinationZoneId) {
        this.destinationZoneId = destinationZoneId;
    }

    public Double getEstimatedDistanceKm() {
        return estimatedDistanceKm;
    }

    public void setEstimatedDistanceKm(Double estimatedDistanceKm) {
        this.estimatedDistanceKm = estimatedDistanceKm;
    }

    public Double getEstimatedDurationMin() {
        return estimatedDurationMin;
    }

    public void setEstimatedDurationMin(Double estimatedDurationMin) {
        this.estimatedDurationMin = estimatedDurationMin;
    }

    public Long getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(Long timestamp) {
        this.timestamp = timestamp;
    }
}