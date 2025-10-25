package com.pricing.flink.serializer;

import com.pricing.flink.model.PriceUpdate;
import org.apache.flink.api.common.serialization.SerializationSchema;

import java.nio.ByteBuffer;

public class PriceUpdateKeySerializer implements SerializationSchema<PriceUpdate> {
    
    @Override
    public byte[] serialize(PriceUpdate update) {
        // Use zone_id as key for partitioning
        return ByteBuffer.allocate(4).putInt(update.getZoneId()).array();
    }
}

