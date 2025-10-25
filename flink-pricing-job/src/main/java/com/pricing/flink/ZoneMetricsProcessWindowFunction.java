package com.pricing.flink;

import com.pricing.flink.model.ZoneMetrics;
import org.apache.flink.streaming.api.functions.windowing.ProcessWindowFunction;
import org.apache.flink.streaming.api.windowing.windows.TimeWindow;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class ZoneMetricsProcessWindowFunction
        extends ProcessWindowFunction<ZoneMetrics, ZoneMetrics, Integer, TimeWindow> {

    private static final Logger logger = LoggerFactory.getLogger(ZoneMetricsProcessWindowFunction.class);

    @Override
    public void process(Integer zoneId, Context context, Iterable<ZoneMetrics> elements, Collector<ZoneMetrics> out) throws Exception {
        ZoneMetrics metrics = elements.iterator().next();

        metrics.setWindowStart(context.window().getStart());
        metrics.setWindowEnd(context.window().getEnd());

        // Cap ratio at 999.0 to prevent database overflow (DECIMAL(10,4) max ~999,999.9999)
        double ratio = metrics.getSupply() > 0 ?
                (double) metrics.getDemand() / metrics.getSupply() :
                (metrics.getDemand() > 0 ? 999.0 : 0.0);
        
        metrics.setRatio(ratio);

        logger.info("Zone {} window [{}ms-{}ms]: demand={}, supply={}, ratio={}",
                zoneId, metrics.getWindowStart(), metrics.getWindowEnd(),
                metrics.getDemand(), metrics.getSupply(), ratio);

        out.collect(metrics);
    }
}
