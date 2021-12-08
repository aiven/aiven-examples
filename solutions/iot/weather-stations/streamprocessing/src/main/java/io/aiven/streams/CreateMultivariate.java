package io.aiven.streams;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.common.utils.Bytes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.*;
import org.apache.kafka.streams.kstream.Suppressed.BufferConfig;
import org.apache.kafka.streams.state.SessionStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import fi.saily.tmsdemo.DigitrafficMessage;
import fi.saily.tmsdemo.DigitrafficMessageMV;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

@Component
@Profile("multivariate")
public class CreateMultivariate {
    private static Logger logger = LoggerFactory.getLogger(CalculationsTopology.class);        
    
    private CreateMultivariate() {
        /*
         * Private Constructor will prevent the instantiation of this class directly
         */
    }

    @Bean    
    public static Topology kafkaStreamTopology(@Value("${spring.application.schema-registry}") String schemaRegistryUrl) {
            
        final StreamsBuilder streamsBuilder = new StreamsBuilder();
        
        // schema registry
        Map<String, String> serdeConfig = new HashMap<>();
        serdeConfig.put("schema.registry.url", schemaRegistryUrl);
        serdeConfig.put("basic.auth.credentials.source", "URL");
        final Serde<DigitrafficMessage> valueSerde = new SpecificAvroSerde<>();
        final Serde<DigitrafficMessageMV> valueMvSerde = new SpecificAvroSerde<>(); 
        valueSerde.configure(serdeConfig, false);
        valueMvSerde.configure(serdeConfig, false);

        Grouped<String, DigitrafficMessage> groupedMessage = Grouped.with(Serdes.String(), valueSerde);
        
        streamsBuilder.stream("observations.weather.municipality", 
            Consumed.with(Serdes.String(), valueSerde).withTimestampExtractor(new ObservationTimestampExtractor()))        
        .filter((k, v) -> v.getName() != null)        
        .groupByKey(groupedMessage) 
        .windowedBy(SessionWindows.with(Duration.ofMinutes(1)).grace(Duration.ofMinutes(15)))                
        .aggregate(
            () -> new DigitrafficMessageMV(-1, 0L, "", "", "", new HashMap<>()) , /* initializer */
            (aggKey, newValue, aggValue) -> {
                if (aggValue.getRoadStationId() < 0) {
                    aggValue.setMunicipality(newValue.getMunicipality());
                    aggValue.setProvince(newValue.getProvince());
                    aggValue.setGeohash(newValue.getGeohash());
                    aggValue.setRoadStationId(newValue.getRoadStationId());
                    aggValue.setMeasuredTime(newValue.getMeasuredTime());
                }
                Map<String, Double> m = aggValue.getMeasurements();
                m.put(newValue.getName(), newValue.getSensorValue());
                return aggValue;                
            }, /* adder */
            (aggKey, leftAggValue, rightAggValue) -> {
                leftAggValue.getMeasurements().putAll(rightAggValue.getMeasurements());
                return leftAggValue;
            }, /* session merger */
                Materialized.<String, DigitrafficMessageMV, SessionStore<Bytes, byte[]>>as("multivariate-state-store")
            .withValueSerde(valueMvSerde)) /* serde for aggregate value */
        .suppress(Suppressed.untilWindowCloses(BufferConfig.unbounded()))
        .toStream()
        .map((key, value) -> new KeyValue<>(String.valueOf(value.getRoadStationId()), value))
        .to("observations.weather.multivariate", Produced.with(Serdes.String(), valueMvSerde));
        
        
        return streamsBuilder.build();
    }
    
    
    
}
