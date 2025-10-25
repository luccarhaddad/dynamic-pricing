package com.pricing.flink.function;

import com.pricing.flink.model.PriceUpdate;
import com.pricing.flink.model.ZoneMetrics;
import org.apache.flink.api.common.functions.MapFunction;

public class SurgeCalculationFunction implements MapFunction<ZoneMetrics, PriceUpdate> {

    @Override
    public PriceUpdate map(ZoneMetrics metrics) throws Exception {
        double surgeMultiplier = calculateSurgeMultiplier(metrics.getRatio());

        return new PriceUpdate(
                metrics.getZoneId(),
                metrics.getWindowStart(),
                metrics.getWindowEnd(),
                metrics.getDemand(),
                metrics.getSupply(),
                metrics.getRatio(),
                surgeMultiplier,
                metrics.getWindowEnd() // Deterministic timestamp from window
        );
    }

    private double calculateSurgeMultiplier(double ratio) {
        // More sensitive surge pricing - starts increasing at ratio 0.5
        if (ratio <= 0.5) {
            return 1.0; // Lots of drivers, no surge
        } else if (ratio <= 0.8) {
            return 1.0 + (ratio - 0.5) * 1.0; // Gentle increase 1.0x -> 1.3x
        } else if (ratio <= 1.2) {
            return 1.3 + (ratio - 0.8) * 1.75; // Steeper increase 1.3x -> 2.0x
        } else if (ratio <= 2.0) {
            return 2.0 + (ratio - 1.2) * 2.5; // Steep increase 2.0x -> 4.0x
        } else if (ratio <= 3.0) {
            return 4.0 + (ratio - 2.0) * 1.5; // Increase 4.0x -> 5.5x
        } else {
            return Math.min(7.0, 5.5 + (ratio - 3.0) * 0.75); // Capped at 7.0x
        }
    }
}
