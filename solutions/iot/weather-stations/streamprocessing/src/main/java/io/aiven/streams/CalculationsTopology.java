package io.aiven.streams;

import java.time.Duration;
import java.util.HashMap;
import java.util.Map;

import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.*;
import org.apache.kafka.streams.kstream.Suppressed.BufferConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import fi.saily.tmsdemo.CountAndSum;
import fi.saily.tmsdemo.DigitrafficAggregate;
import fi.saily.tmsdemo.DigitrafficMessage;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

@Component
@Profile("calculations")
public class CalculationsTopology {
    private static Logger logger = LoggerFactory.getLogger(CalculationsTopology.class);        
    
    private CalculationsTopology() {
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
        Serde<DigitrafficMessage> valueSerde = new SpecificAvroSerde<>();
        Serde<CountAndSum> aggrSerde = new SpecificAvroSerde<>();
        Serde<DigitrafficAggregate> resultSerde = new SpecificAvroSerde<>();        
        
        valueSerde.configure(serdeConfig, false);
        aggrSerde.configure(serdeConfig, false);
        resultSerde.configure(serdeConfig, false);

        Grouped<String, DigitrafficMessage> groupedMessage = Grouped.with(Serdes.String(), valueSerde);
        
        KTable<Windowed<String>, DigitrafficAggregate> windows = streamsBuilder.stream("observations.weather.processed", 
            Consumed.with(Serdes.String(), valueSerde).withTimestampExtractor(new ObservationTimestampExtractor()))        
        .filter((k, v) -> v.getName() != null && v.getName().contentEquals("ILMA"))
        .selectKey((key, value) -> key + "-" + String.valueOf(value.getId()))
        .groupByKey(groupedMessage) 
        .windowedBy(TimeWindows.of(Duration.ofMinutes(60)).advanceBy(Duration.ofMinutes(60)).grace(Duration.ofMinutes(10)))                
        .aggregate(() -> new CountAndSum(0, 0, "", 0L, 0.0), 
            (key, value, aggregate) -> {
                if (aggregate.getRoadStationId() == 0) {
                    aggregate.setRoadStationId(value.getRoadStationId());
                    aggregate.setId(value.getId());
                    aggregate.setName(value.getName());
                }
                aggregate.setCount(aggregate.getCount() + 1);
                aggregate.setSum(aggregate.getSum() + value.getSensorValue());
                return aggregate;
            }, Materialized.with(Serdes.String(), aggrSerde))  
        .suppress(Suppressed.untilWindowCloses(BufferConfig.unbounded()))      
        .mapValues((key, value) -> DigitrafficAggregate.newBuilder()
            .setId(value.getId())
            .setRoadStationId(value.getRoadStationId())
            .setName(value.getName())
            .setSensorValue(value.getSum() / value.getCount())
            .setMeasuredTime(key.window().end())
            .build()
        );

        windows
            .toStream()
            .map((key, value) -> 
                new KeyValue<String, DigitrafficAggregate>(String.valueOf(value.getRoadStationId()), value))
            .to("observations.weather.avg-air-temperature", Produced.with(Serdes.String(), resultSerde));
                        
        return streamsBuilder.build();
    }
    
    
    
}
