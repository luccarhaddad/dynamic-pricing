package com.pricing.flink;

import com.pricing.flink.model.NormalizedEvent;
import com.pricing.flink.model.ZoneMetrics;
import org.apache.flink.api.common.functions.AggregateFunction;

public class ZoneMetricsAggregator implements AggregateFunction<NormalizedEvent, ZoneMetricsAggregator.Accumulator, ZoneMetrics> {

    public static class Accumulator {
        int zoneId;
        int rideCount = 0;
        int availableDrivers = 0;

        public Accumulator() {}

        public Accumulator(int zoneId) {
            this.zoneId = zoneId;
        }
    }

    @Override
    public Accumulator createAccumulator() {
        return new Accumulator();
    }

    @Override
    public Accumulator add(NormalizedEvent event, Accumulator accumulator) {
        accumulator.zoneId = event.getZoneId();

        if ("RIDE".equals(event.getKind())) {
            accumulator.rideCount++;
        } else if ("HEARTBEAT".equals(event.getKind()) && "AVAILABLE".equals(event.getStatus())) {
            accumulator.availableDrivers++;
        }

        return accumulator;
    }

    @Override
    public ZoneMetrics getResult(Accumulator accumulator) {
        return new ZoneMetrics(
                accumulator.zoneId,
                0,
                0,
                accumulator.rideCount,
                accumulator.availableDrivers
        );
    }

    @Override
    public Accumulator merge(Accumulator a, Accumulator b) {
        a.rideCount += b.rideCount;
        a.availableDrivers += b.availableDrivers;
        return a;
    }
}
