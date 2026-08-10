package io.aiven.ingest;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;

@SpringBootApplication
@ConfigurationPropertiesScan
public class IngestServiceApplication {

    public static void main(String[] args) {
        SpringApplication.run(IngestServiceApplication.class, args);
    }
}
