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
import org.apache.flink.streaming.api.windowing.assigners.TumblingEventTimeWindows;
import org.apache.flink.streaming.api.environment.CheckpointConfig;
import org.apache.flink.streaming.api.CheckpointingMode;
import org.apache.flink.runtime.state.hashmap.HashMapStateBackend;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Duration;

public class PricingJobMain {

    private static final Logger logger = LoggerFactory.getLogger(PricingJobMain.class);

    private static final int CHECKPOINT_INTERVAL = 10000;
    private static final int MIN_PAUSE_BETWEEN_CHECKPOINTS = 3000;
    private static final int CHECKPOINT_TIMEOUT = 600000;

    private static final int PARALLELISM = 8;
    private static final int WATERMARK_INTERVAL = 10;
    private static final int ALLOWED_LATENESS = 10;
    private static final int EVENT_TIME_WINDOW = 5;

    private static final String GROUP_ID = "flink-pricing-job";
    private static final String RIDE_REQUESTS_TOPIC = "ride-requests";
    private static final String DRIVER_HEARTBEATS_TOPIC = "driver-heartbeats";
    private static final String PRICE_UPDATES_TOPIC = "price-updates";

    private static final String RIDE_REQUESTS_SOURCE = "ride-requests-source";
    private static final String DRIVER_HEARTBEATS_SOURCE = "driver-heartbeats-source";
    private static final String NORMALIZE_RIDES_REQS = "normalize-ride-requests";
    private static final String NORMALIZE_DRIVERS_HBS = "normalize-driver-heartbeats";
    private static final String NORMALIZED_UNION = "unified-events";
    private static final String ZONE_METRIC_AGG = "zone-metrics-aggregation";
    private static final String SURGE_CALC = "surge-calculation";
    private static final String PRICE_UPDATE_SINK = "price-updates-kafka-sink";

    public static void main(String[] args) throws Exception {
        logger.info("Starting Dynamic Pricing Flink Job");

        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        configureEnvironment(env);

        KafkaSource<String> rideRequestsSource = createRideRequestsSource();
        KafkaSource<String> driverHeartbeatsSource = createDriverHeartbeatsSource();

        DataStream<PriceUpdate> priceUpdates = buildPricingPipeline(env, rideRequestsSource, driverHeartbeatsSource);
        configureSink(priceUpdates);

        logger.info("Executing Dynamic Pricing Job...");
        env.execute("Dynamic Pricing Job");
    }

    private static void configureEnvironment(StreamExecutionEnvironment env) {
        env.setParallelism(PARALLELISM);
        
        String checkpointDir = System.getenv().getOrDefault("CHECKPOINT_DIR", "file:///app/checkpoints");
        
        env.setStateBackend(new HashMapStateBackend());
        env.getCheckpointConfig().setCheckpointStorage(checkpointDir);
        
        logger.info("Checkpoint storage configured at: {}", checkpointDir);

        env.enableCheckpointing(CHECKPOINT_INTERVAL);

        CheckpointConfig checkpointConfig = env.getCheckpointConfig();
        checkpointConfig.setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
        checkpointConfig.setMinPauseBetweenCheckpoints(MIN_PAUSE_BETWEEN_CHECKPOINTS);
        checkpointConfig.setCheckpointTimeout(CHECKPOINT_TIMEOUT);
        checkpointConfig.setMaxConcurrentCheckpoints(1);
        checkpointConfig.setExternalizedCheckpointCleanup(
                CheckpointConfig.ExternalizedCheckpointCleanup.RETAIN_ON_CANCELLATION
        );
        checkpointConfig.enableUnalignedCheckpoints();
        
        checkpointConfig.setTolerableCheckpointFailureNumber(3);

        logger.info("Environment configured: parallelism={}, checkpoint_interval={}ms, mode=EXACTLY_ONCE",
                PARALLELISM, CHECKPOINT_INTERVAL);
    }

    private static KafkaSource<String> createRideRequestsSource() {
        logger.info("Creating Kafka source for topic: {}", RIDE_REQUESTS_TOPIC);
        return KafkaSource.<String>builder()
                .setBootstrapServers(getKafkaBrokers())
                .setTopics(RIDE_REQUESTS_TOPIC)
                .setGroupId(GROUP_ID)
                .setStartingOffsets(OffsetsInitializer.committedOffsets(
                        org.apache.kafka.clients.consumer.OffsetResetStrategy.LATEST))
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();
    }

    private static KafkaSource<String> createDriverHeartbeatsSource() {
        logger.info("Creating Kafka source for topic: {}", DRIVER_HEARTBEATS_TOPIC);
        return KafkaSource.<String>builder()
                .setBootstrapServers(getKafkaBrokers())
                .setTopics(DRIVER_HEARTBEATS_TOPIC)
                .setGroupId(GROUP_ID)
                .setStartingOffsets(OffsetsInitializer.committedOffsets(
                        org.apache.kafka.clients.consumer.OffsetResetStrategy.LATEST))
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();
    }

    private static DataStream<PriceUpdate> buildPricingPipeline(
            StreamExecutionEnvironment env,
            KafkaSource<String> rideRequestsSource,
            KafkaSource<String> driverHeartbeatsSource) {

        DataStream<String> rideRequestStream = env
                .fromSource(rideRequestsSource, WatermarkStrategy.noWatermarks(), RIDE_REQUESTS_SOURCE);

        DataStream<String> driverHeartbeatStream = env
                .fromSource(driverHeartbeatsSource, WatermarkStrategy.noWatermarks(), DRIVER_HEARTBEATS_SOURCE);

        logger.info("Created input streams for ride-requests and driver-heartbeats");

        DataStream<NormalizedEvent> normalizedRides = rideRequestStream
                .flatMap(new EventNormalizationFunction(EventKind.RIDE.getValue()))
                .assignTimestampsAndWatermarks(
                        WatermarkStrategy.<NormalizedEvent>forBoundedOutOfOrderness(Duration.ofSeconds(WATERMARK_INTERVAL))
                                .withTimestampAssigner((event, timestamp) -> event.getTimestamp())
                                .withIdleness(Duration.ofSeconds(WATERMARK_INTERVAL + 5))
                )
                .name(NORMALIZE_RIDES_REQS);

        DataStream<NormalizedEvent> normalizedHeartbeats = driverHeartbeatStream
                .flatMap(new EventNormalizationFunction(EventKind.HEARTBEAT.getValue()))
                .assignTimestampsAndWatermarks(
                        WatermarkStrategy.<NormalizedEvent>forBoundedOutOfOrderness(Duration.ofSeconds(WATERMARK_INTERVAL))
                                .withTimestampAssigner((event, timestamp) -> event.getTimestamp())
                                .withIdleness(Duration.ofSeconds(WATERMARK_INTERVAL + 5))
                )
                .name(NORMALIZE_DRIVERS_HBS);

        DataStream<NormalizedEvent> unifiedStream = normalizedRides
                .union(normalizedHeartbeats);

        logger.info("Created unified event stream with event-time watermarks");

        DataStream<ZoneMetrics> zoneMetrics = unifiedStream
                .keyBy(NormalizedEvent::getZoneId)
                .window(TumblingEventTimeWindows.of(Time.seconds(EVENT_TIME_WINDOW)))
                .allowedLateness(Time.seconds(ALLOWED_LATENESS))
                .aggregate(new ZoneMetricsAggregator(), new ZoneMetricsProcessWindowFunction())
                .name(ZONE_METRIC_AGG);

        DataStream<PriceUpdate> priceUpdates = zoneMetrics
                .map(new SurgeCalculationFunction())
                .name(SURGE_CALC);

        logger.info("Pipeline configured: window={}s (event-time), watermark={}s, allowed_lateness={}s",
                EVENT_TIME_WINDOW, WATERMARK_INTERVAL, ALLOWED_LATENESS);

        return priceUpdates;
    }

    private static void configureSink(DataStream<PriceUpdate> priceUpdates) {
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

        priceUpdates.sinkTo(priceSink).name(PRICE_UPDATE_SINK);
        priceUpdates.print("PRICE-UPDATE");

        logger.info("Configured Kafka sink to topic: {}", PRICE_UPDATES_TOPIC);
    }

    private static String getKafkaBrokers() {
        return System.getenv().getOrDefault("KAFKA_BROKERS", "localhost:19092");
    }
}
