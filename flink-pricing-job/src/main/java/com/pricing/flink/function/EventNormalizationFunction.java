package com.pricing.flink.function;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.pricing.flink.model.NormalizedEvent;
import org.apache.flink.api.common.functions.FlatMapFunction;
import com.pricing.flink.model.EventKind;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class EventNormalizationFunction implements FlatMapFunction<String, NormalizedEvent> {

    private static final Logger logger = LoggerFactory.getLogger(EventNormalizationFunction.class);

    private final String eventType;
    private static final ObjectMapper objectMapper = new ObjectMapper();

    public EventNormalizationFunction(String eventType) {
        this.eventType = eventType;
    }

    @Override
    public void flatMap(String jsonString, Collector<NormalizedEvent> collector) throws Exception {
        try {
            JsonNode jsonNode = objectMapper.readTree(jsonString);

            if (EventKind.RIDE.getValue().equals(eventType)) {
                int zoneId = jsonNode.get("zone_id").asInt();
                long timestamp = jsonNode.get("ts_event").asLong();

                collector.collect(NormalizedEvent.forRide(zoneId, timestamp));
            }

            if (EventKind.HEARTBEAT.getValue().equals(eventType)) {
                int zoneId = jsonNode.get("zone_id").asInt();
                long timestamp = jsonNode.get("ts_event").asLong();
                String status = jsonNode.get("status").asText();

                collector.collect(NormalizedEvent.forHeartbeat(zoneId, timestamp, status));
            }
        } catch (Exception e) {
            logger.error("Failed to parse {} event: {}, error: {}", eventType, jsonString, e.getMessage());
        }
    }
}
