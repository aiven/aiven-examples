package io.aiven.ingest.bench;

import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

@Component
public class BenchmarkReporterFactory {

    private final MeterRegistry registry;

    public BenchmarkReporterFactory(MeterRegistry registry) {
        this.registry = registry;
    }

    public BenchmarkReporter forRun(String runLabel) {
        return new BenchmarkReporter(registry, runLabel);
    }
}
