package com.pricing.flink;

import com.pricing.flink.function.EventNormalizationFunction;
import com.pricing.flink.function.SurgeCalculationFunction;
import com.pricing.flink.model.EventKind;
import com.pricing.flink.model.NormalizedEvent;
import com.pricing.flink.model.PriceUpdate;
import com.pricing.flink.model.ZoneMetrics;
import com.pricing.flink.serializer.PriceUpdateKeySerializer;
import com.pricing.flink.serializer.PriceUpdateSerializationSchema;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.streaming.api.windowing.time.Time;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;
import java.util.Properties;

public class PricingJobMain {

    private static final Logger logger = LoggerFactory.getLogger(PricingJobMain.class);

    private static final int CHECKPOINT_INTERVAL = 15000;
    private static final int PARALLELISM = 4;
    private static final int WATERMARK_INTERVAL = 10;
    private static final int ALLOWED_LATENESS = 10;
    private static final int PROCESSING_TIME_WINDOW = 3;  // 3 seconds - much faster updates!

    private static final String GROUP_ID = "flink-pricing-job";
    private static final String RIDE_REQUESTS_TOPIC = "ride-requests";
    private static final String RIDE_REQUESTS_SOURCE = "ride-requests-source";
    private static final String DRIVER_HEARTBEATS_TOPIC = "driver-heartbeats";
    private static final String DRIVER_HEARTBEATS_SOURCE = "driver-heartbeats-source";
    private static final String PRICE_UPDATES_TOPIC = "price-updates";

    private static final String NORMALIZE_RIDES_REQS = "normalize-ride-requests";
    private static final String NORMALIZE_DRIVERS_HBS = "normalize-driver-heartbeats";

    private static final String NORMALIZED_UNION = "unified-events";
    private static final String ZONE_METRIC_AGG = "zone-metrics-aggregation";
    private static final String SURGE_CALC = "surge-calculation";
    private static final String PRICE_UPDATE_SINK = "price-updates-kafka-sink";

    public static void main(String[] args) throws Exception {
        logger.info("Starting Dynamic Pricing Flink Job");

        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.enableCheckpointing(CHECKPOINT_INTERVAL);
        env.setParallelism(PARALLELISM);

        Properties kafkaProperties = new Properties();
        kafkaProperties.setProperty("bootstrap.servers", getKafkaBrokers());
        kafkaProperties.setProperty("group.id", GROUP_ID);

        logger.info("Connecting to Kafka at: {}", getKafkaBrokers());

        // Kafka Sources
        KafkaSource<String> rideRequestsSource = KafkaSource.<String>builder()
                .setBootstrapServers(getKafkaBrokers())
                .setTopics(RIDE_REQUESTS_TOPIC)
                .setGroupId(GROUP_ID)
                .setStartingOffsets(OffsetsInitializer.latest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();

        KafkaSource<String> driverHeartbeatsSource = KafkaSource.<String>builder()
                .setBootstrapServers(getKafkaBrokers())
                .setTopics(DRIVER_HEARTBEATS_TOPIC)
                .setGroupId(GROUP_ID)
                .setStartingOffsets(OffsetsInitializer.latest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();

        // Data Streams with watermarks
        WatermarkStrategy<String> watermarkStrategy = WatermarkStrategy
                .<String>forBoundedOutOfOrderness(Duration.ofSeconds(WATERMARK_INTERVAL))
                .withTimestampAssigner((event, timestamp) -> System.currentTimeMillis());

        DataStream<String> rideRequestStream = env
                .fromSource(rideRequestsSource, watermarkStrategy, RIDE_REQUESTS_SOURCE);

        DataStream<String> driverHeartbeatStream = env
                .fromSource(driverHeartbeatsSource, watermarkStrategy, DRIVER_HEARTBEATS_SOURCE);

        logger.info("Created Kafka sources for ride-requests and driver-heartbeats");

        DataStream<NormalizedEvent> normalizedRides = rideRequestStream
                .flatMap(new EventNormalizationFunction(EventKind.RIDE.getValue()))
                .name(NORMALIZE_RIDES_REQS);

        DataStream<NormalizedEvent> normalizedHeartBeats = driverHeartbeatStream
                .flatMap(new EventNormalizationFunction(EventKind.HEARTBEAT.getValue()))
                .name(NORMALIZE_DRIVERS_HBS);

        // TODO: check naming
        DataStream<NormalizedEvent> unifiedStream = normalizedRides
                .union(normalizedHeartBeats)
                .map(x->x)
                .name(NORMALIZED_UNION);

        logger.info("Created unified event stream");

        DataStream<ZoneMetrics> zoneMetrics = unifiedStream
                .keyBy(NormalizedEvent::getZoneId)
                .window(TumblingProcessingTimeWindows.of(Time.seconds(PROCESSING_TIME_WINDOW)))
                .allowedLateness(Time.seconds(ALLOWED_LATENESS))
                .aggregate(new ZoneMetricsAggregator(), new ZoneMetricsProcessWindowFunction())
                .name(ZONE_METRIC_AGG);

        DataStream<PriceUpdate> priceUpdates = zoneMetrics
                .map(new SurgeCalculationFunction())
                .name(SURGE_CALC);

        // Create Kafka Sink for price updates
        KafkaSink<PriceUpdate> priceSink = KafkaSink.<PriceUpdate>builder()
                .setBootstrapServers(getKafkaBrokers())
                .setRecordSerializer(
                    KafkaRecordSerializationSchema.<PriceUpdate>builder()
                        .setTopic(PRICE_UPDATES_TOPIC)
                        .setValueSerializationSchema(new PriceUpdateSerializationSchema())
                        .setKeySerializationSchema(new PriceUpdateKeySerializer())
                        .build()
                )
                .setDeliveryGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                .build();

        // Publish to Kafka
        priceUpdates.sinkTo(priceSink).name(PRICE_UPDATE_SINK);
        
        // Also print for debugging
        priceUpdates.print("PRICE-UPDATE");

        logger.info("Price calculation pipeline configured with Kafka sink to topic: {}", PRICE_UPDATES_TOPIC);
        logger.info("Window: {}s tumbling, Watermark: {}s, Allowed lateness: {}s",
                PROCESSING_TIME_WINDOW, WATERMARK_INTERVAL, ALLOWED_LATENESS);

        env.execute("Dynamic Pricing Job");
    }

    private static String getKafkaBrokers() {
        return System.getenv().getOrDefault("KAFKA_BROKERS", "localhost:19092");
    }
}
