package com.pricing.flink.serializer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.pricing.flink.model.PriceUpdate;
import org.apache.flink.api.common.serialization.SerializationSchema;

public class PriceUpdateSerializationSchema implements SerializationSchema<PriceUpdate> {
    
    private static final ObjectMapper objectMapper = new ObjectMapper();
    
    @Override
    public byte[] serialize(PriceUpdate update) {
        try {
            ObjectNode node = objectMapper.createObjectNode();
            node.put("zone_id", update.getZoneId());
            node.put("window_start", update.getWindowStart());
            node.put("window_end", update.getWindowEnd());
            node.put("demand", update.getDemand());
            node.put("supply", update.getSupply());
            node.put("ratio", update.getRatio());
            node.put("surge_multiplier", update.getSurgeMultiplier());
            node.put("ts_compute", update.getTsCompute());
            
            return objectMapper.writeValueAsBytes(node);
        } catch (Exception e) {
            throw new RuntimeException("Failed to serialize PriceUpdate", e);
        }
    }
}

