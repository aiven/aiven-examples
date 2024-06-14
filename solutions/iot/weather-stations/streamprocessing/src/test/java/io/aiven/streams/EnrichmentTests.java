package io.aiven.streams;

import java.io.File;
import java.io.IOException;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.util.Collections;
import java.util.Map;
import java.util.Properties;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.common.serialization.Serde;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KeyValue;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.TestInputTopic;
import org.apache.kafka.streams.TestOutputTopic;
import org.apache.kafka.streams.Topology;
import org.apache.kafka.streams.TopologyTestDriver;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerde;
import org.springframework.kafka.support.serializer.JsonSerializer;

import fi.saily.tmsdemo.DigitrafficMessage;
import io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException;
import io.confluent.kafka.schemaregistry.testutil.MockSchemaRegistry;
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.GenericAvroSerde;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

import static org.hamcrest.CoreMatchers.equalTo;
import static org.hamcrest.MatcherAssert.assertThat;

class EnrichmentTests {

    private Logger logger = LoggerFactory.getLogger(EnrichmentTests.class);

    private static final String SCHEMA_REGISTRY_SCOPE = EnrichmentTests.class.getName();
    private static final String MOCK_SCHEMA_REGISTRY_URL = "mock://" + SCHEMA_REGISTRY_SCOPE;

    protected TestInputTopic<String, JsonNode> rawInputTopic;
    protected TestOutputTopic<String, DigitrafficMessage> processedOutputTopic;
    protected TestInputTopic<String, DigitrafficMessage> processedInputTopic;
    protected TestInputTopic<String, GenericRecord> stationInputTopic;
    protected TestOutputTopic<String, DigitrafficMessage> enrichedOutputTopic;

    private TopologyTestDriver testDriver;
    
    @BeforeEach
    public void setup() throws IOException, RestClientException {        

        Properties config = new Properties();
        config.setProperty(StreamsConfig.APPLICATION_ID_CONFIG, "tms-test-enrichment");
        config.setProperty(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "foo:1234");
        config.setProperty(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        config.setProperty(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, JsonSerde.class.getName());
        config.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, true);
        config.put(JsonDeserializer.TRUSTED_PACKAGES, "*");
        config.setProperty(JsonDeserializer.VALUE_DEFAULT_TYPE, JsonNode.class.getName());

        Map<String, String> schemaRegistryConfig = Collections
        .singletonMap(AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, MOCK_SCHEMA_REGISTRY_URL);

        Serde<String> stringSerde = Serdes.String();

        SpecificAvroSerde<DigitrafficMessage> digitrafficSerde = new SpecificAvroSerde<>();
        digitrafficSerde.configure(schemaRegistryConfig, false);

        Serde<GenericRecord> stationSerde = new GenericAvroSerde();
        stationSerde.configure(schemaRegistryConfig, false);        

        Topology topology = EnrichmentTopology.kafkaStreamTopology(MOCK_SCHEMA_REGISTRY_URL);
        logger.info(topology.describe().toString());
        testDriver = new TopologyTestDriver(topology, config);        

        rawInputTopic = testDriver.createInputTopic(
            "observations.weather.raw",
            stringSerde.serializer(),
            new JsonSerializer<>());

        processedOutputTopic = testDriver.createOutputTopic(
            "observations.weather.processed",
            stringSerde.deserializer(),
            digitrafficSerde.deserializer());

        processedInputTopic = testDriver.createInputTopic(
            "observations.weather.processed",
            stringSerde.serializer(),
            digitrafficSerde.serializer()); 

        stationInputTopic = testDriver.createInputTopic(
            "tms-demo-pg.public.weather_stations",
            stringSerde.serializer(),
            stationSerde.serializer());

        enrichedOutputTopic = testDriver.createOutputTopic(
            "observations.weather.municipality",
            stringSerde.deserializer(),
            digitrafficSerde.deserializer());
    }

    @AfterEach
    void afterEach() {        
        testDriver.close();
        MockSchemaRegistry.dropScope(SCHEMA_REGISTRY_SCOPE);
    }

    @Test
    public void shouldEnrichMunicipality() throws IOException, RestClientException  {

        Path resourceDirectory = Paths.get("src","test","resources");
        String absolutePath = resourceDirectory.toFile().getAbsolutePath() + "/station.avsc";         
        
        Schema schema = new Schema.Parser().parse(new File(absolutePath));            
        GenericRecord record = new GenericData.Record(schema);
        record.put("roadstationid", 12016);
        record.put("name", "somename");
        record.put("municipality", "Kärsämäki");
        record.put("province", "Pohjois-Pohjanmaa");
        record.put("latitude", 64.006442);
        record.put("longitude", 25.755648);
        
        stationInputTopic.pipeInput("12016", record);

        processedInputTopic.pipeInput("12016", DigitrafficMessage.newBuilder()
            .setId(132)
            .setRoadStationId(12016)
            .setName("KUITUVASTE_SUURI_1")
            .setSensorValue(0.0f)
            .setSensorUnit("###")
            .setMeasuredTime(Instant.parse("2020-12-02T20:42:00Z").toEpochMilli()).build());

        assertThat(enrichedOutputTopic.readKeyValue(), equalTo(new KeyValue<>("12016", 
            DigitrafficMessage.newBuilder()
                .setId(132)
                .setRoadStationId(12016)
                .setName("KUITUVASTE_SUURI_1")
                .setSensorValue(0.0f)
                .setSensorUnit("###")
                .setMunicipality("Kärsämäki")
                .setProvince("Pohjois-Pohjanmaa")
                .setGeohash("ue6k4h")
                .setMeasuredTime(Instant.parse("2020-12-02T20:42:00Z").toEpochMilli()).build())));
        
    }    

    @Test
    public void shouldGenerateAvro() throws IOException, RestClientException {
        ObjectMapper mapper = new ObjectMapper();
        JsonNode jsonObj = mapper.readTree("{\"id\": 132, \"roadStationId\": 12016, \"name\": \"KUITUVASTE_SUURI_1\", \"oldName\": " +
            "\"fiberresponsebig1\", \"shortName\": \"KVaS1 \", \"sensorValue\": 0.0, \"sensorUnit\": \"###\", " +
            "\"measuredTime\": \"2020-12-02T20:42:00Z\"}");
        rawInputTopic.pipeInput("12016", jsonObj);

        assertThat(processedOutputTopic.readKeyValue(), equalTo(new KeyValue<>("12016", 
            DigitrafficMessage.newBuilder()
                .setId(132)
                .setRoadStationId(12016)
                .setName("KUITUVASTE_SUURI_1")
                .setSensorValue(0.0f)
                .setSensorUnit("###")
                .setMeasuredTime(Instant.parse("2020-12-02T20:42:00Z").toEpochMilli()).build())));
        
    }

}
