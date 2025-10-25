package com.pricing.api.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.math.BigDecimal;
import java.time.OffsetDateTime;

public class ZonePriceResponse {

    @JsonProperty("zone_id")
    private Integer zoneId;

    @JsonProperty("surge_multiplier")
    private BigDecimal surgeMultiplier;

    @JsonProperty("quoted_fare")
    private BigDecimal quotedFare;

    @JsonProperty("updated_at")
    private OffsetDateTime updatedAt;

    @JsonProperty("demand")
    private Integer demand;

    @JsonProperty("supply")
    private Integer supply;

    @JsonProperty("ratio")
    private BigDecimal ratio;

    public ZonePriceResponse() {}

    public ZonePriceResponse(Integer zoneId, BigDecimal surgeMultiplier, BigDecimal quotedFare, OffsetDateTime updatedAt) {
        this.zoneId = zoneId;
        this.surgeMultiplier = surgeMultiplier;
        this.quotedFare = quotedFare;
        this.updatedAt = updatedAt;
    }

    public ZonePriceResponse(Integer zoneId, BigDecimal surgeMultiplier, BigDecimal quotedFare, 
                            OffsetDateTime updatedAt, Integer demand, Integer supply, BigDecimal ratio) {
        this.zoneId = zoneId;
        this.surgeMultiplier = surgeMultiplier;
        this.quotedFare = quotedFare;
        this.updatedAt = updatedAt;
        this.demand = demand;
        this.supply = supply;
        this.ratio = ratio;
    }

    public Integer getZoneId() {
        return zoneId;
    }

    public void setZoneId(Integer zoneId) {
        this.zoneId = zoneId;
    }

    public BigDecimal getSurgeMultiplier() {
        return surgeMultiplier;
    }

    public void setSurgeMultiplier(BigDecimal surgeMultiplier) {
        this.surgeMultiplier = surgeMultiplier;
    }

    public BigDecimal getQuotedFare() {
        return quotedFare;
    }

    public void setQuotedFare(BigDecimal quotedFare) {
        this.quotedFare = quotedFare;
    }

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(OffsetDateTime updatedAt) {
        this.updatedAt = updatedAt;
    }

    public Integer getDemand() {
        return demand;
    }

    public void setDemand(Integer demand) {
        this.demand = demand;
    }

    public Integer getSupply() {
        return supply;
    }

    public void setSupply(Integer supply) {
        this.supply = supply;
    }

    public BigDecimal getRatio() {
        return ratio;
    }

    public void setRatio(BigDecimal ratio) {
        this.ratio = ratio;
    }
}