package io.aiven.streams;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import org.apache.avro.generic.GenericRecord;
import org.apache.commons.text.StringEscapeUtils;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsBuilder;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.kstream.Consumed;
import org.apache.kafka.streams.kstream.KStream;
import org.apache.kafka.streams.kstream.KTable;
import org.apache.kafka.streams.kstream.Produced;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Profile;
import org.springframework.kafka.support.serializer.JsonSerde;
import org.springframework.stereotype.Component;

import ch.hsr.geohash.GeoHash;
import fi.saily.tmsdemo.DigitrafficMessage;
import fi.saily.tmsdemo.WeatherStation;
import io.confluent.kafka.streams.serdes.avro.GenericAvroSerde;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

@Component
@Profile("enrichment")
public class EnrichmentTopology {    

    private EnrichmentTopology() {
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
        Serde<GenericRecord> genericSerde = new GenericAvroSerde();        
        valueSerde.configure(serdeConfig, false);
        genericSerde.configure(serdeConfig, false);
        

        // Sourced weather stations from PostreSQL table
        KTable<String, WeatherStation> stationTable = 
        streamsBuilder.table("tms-demo-pg.public.weather_stations", Consumed.with(Serdes.String(), genericSerde))
        .mapValues((key, value) -> WeatherStation.newBuilder()
            .setRoadStationId((Integer)value.get("roadstationid"))
            .setGeohash(calculateGeohash(value))
            .setName("")
            .setMunicipality(value.get("municipality") != null ? value.get("municipality").toString() : "")
            .setProvince(value.get("province") != null ? value.get("province").toString() : "")
            .build());        

        KStream<String, JsonNode> jsonWeatherStream = streamsBuilder.stream("observations.weather.raw", 
            Consumed.with(Serdes.String(), new JsonSerde<>(JsonNode.class)));

        jsonWeatherStream        
        .filter((k, v) -> !k.isBlank() && v.get("measuredTime") != null)
        .map((k,v) -> convertToAvro(v))        
        .to("observations.weather.processed", Produced.with(Serdes.String(), valueSerde));     

        KStream<String, DigitrafficMessage> avroWeatherStream = 
            streamsBuilder.stream("observations.weather.processed", 
        Consumed.with(Serdes.String(), valueSerde).withTimestampExtractor(new ObservationTimestampExtractor()));

        avroWeatherStream
        .filter((k, v) -> !k.isBlank())
        .join(stationTable, (measurement, station) -> 
            DigitrafficMessage.newBuilder(measurement)
            .setMunicipality(StringEscapeUtils.unescapeJava(station.getMunicipality()))
            .setProvince(StringEscapeUtils.unescapeJava(station.getProvince()))
            .setGeohash(station.getGeohash())            
            .build()
        )        
        .to("observations.weather.municipality", Produced.with(Serdes.String(), valueSerde));
        
        return streamsBuilder.build();  
    }

    private static final String calculateGeohash(GenericRecord station) {        
        return GeoHash.geoHashStringWithCharacterPrecision(Double.parseDouble(station.get("latitude").toString()), 
        Double.parseDouble(station.get("longitude").toString()), 6);
    }

    private static final KeyValue<String, DigitrafficMessage> convertToAvro(JsonNode v) {        
        Optional<JsonNode> stationId = Optional.ofNullable(v.get("roadStationId"));
        if (stationId.isPresent()) {            
            Optional<JsonNode> id = Optional.ofNullable(v.get("id"));            
            Optional<JsonNode> name = Optional.ofNullable(v.get("name"));
            Optional<JsonNode> value = Optional.ofNullable(v.get("sensorValue"));
            Optional<JsonNode> time = Optional.ofNullable(v.get("measuredTime"));
            Optional<JsonNode> unit = Optional.ofNullable(v.get("sensorUnit"));
        
            final DigitrafficMessage msg = DigitrafficMessage.newBuilder()
            .setId(id.get().asInt())
            .setName(name.get().asText())
            .setSensorValue(value.get().asDouble())
            .setRoadStationId(stationId.get().asInt())
            .setMeasuredTime(Instant.parse(time.get().asText()).toEpochMilli())
            .setSensorUnit(unit.get().asText())
            .build();
            return KeyValue.pair(stationId.get().asText(), msg);
        } else {
            return KeyValue.pair("", null);
        }

    }
}
