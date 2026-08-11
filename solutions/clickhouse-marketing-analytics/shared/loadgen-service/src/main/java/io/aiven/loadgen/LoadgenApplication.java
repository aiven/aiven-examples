package io.aiven.loadgen;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

/**
 * The load-test producer as a service: simulates the real-world producers
 * (web frontends, mobile devices, backend webhooks) firing events at the
 * ingest service's POST /events - and, like the ingest service's own remote
 * benchmark API, it is drivable entirely over HTTP so it can run where the
 * load SHOULD come from (Aiven Apps, same region as the target) instead of a
 * laptop behind a consumer uplink:
 *
 *   POST /loadtests {"mode":"firehose","rate":50000,"duration_s":60}
 *   GET  /loadtests/{id}     -> live progress / final summary
 */
@SpringBootApplication
@ConfigurationPropertiesScan
public class LoadgenApplication {

    public static void main(String[] args) {
        SpringApplication.run(LoadgenApplication.class, args);
    }
}
