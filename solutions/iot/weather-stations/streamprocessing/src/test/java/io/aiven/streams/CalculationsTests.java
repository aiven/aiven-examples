package io.aiven.streams;

import java.io.IOException;
import java.time.Instant;
import java.util.Collections;
import java.util.Map;
import java.util.Properties;

import com.fasterxml.jackson.databind.JsonNode;
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

import fi.saily.tmsdemo.DigitrafficAggregate;
import fi.saily.tmsdemo.DigitrafficMessage;
import io.confluent.kafka.schemaregistry.client.rest.exceptions.RestClientException;
import io.confluent.kafka.schemaregistry.testutil.MockSchemaRegistry;
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerde;

import static org.hamcrest.CoreMatchers.equalTo;
import static org.hamcrest.MatcherAssert.assertThat;

class CalculationsTests {

    private Logger logger = LoggerFactory.getLogger(CalculationsTests.class);

    private static final String SCHEMA_REGISTRY_SCOPE = CalculationsTests.class.getName();
    private static final String MOCK_SCHEMA_REGISTRY_URL = "mock://" + SCHEMA_REGISTRY_SCOPE;

    protected TestOutputTopic<String, DigitrafficAggregate> avgOutputTopic;
    protected TestInputTopic<String, DigitrafficMessage> processedInputTopic;
    
    private TopologyTestDriver testDriver;
    
    @BeforeEach
    public void setup() throws IOException, RestClientException {        
        

        Map<String, String> schemaRegistryConfig = Collections
        .singletonMap(AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, MOCK_SCHEMA_REGISTRY_URL);

        Serde<String> stringSerde = Serdes.String();

        SpecificAvroSerde<DigitrafficMessage> digitrafficSerde = new SpecificAvroSerde<>();
        digitrafficSerde.configure(schemaRegistryConfig, false);

        SpecificAvroSerde<DigitrafficAggregate> aggrSerde = new SpecificAvroSerde<>();
        aggrSerde.configure(schemaRegistryConfig, false);


        Properties config = new Properties();
        config.setProperty(StreamsConfig.APPLICATION_ID_CONFIG, "tms-test-calculation");
        config.setProperty(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, "foo:1234");
        config.setProperty(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass().getName());
        config.setProperty(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, JsonSerde.class.getName());
        config.put(JsonSerializer.ADD_TYPE_INFO_HEADERS, true);
        config.put(JsonDeserializer.TRUSTED_PACKAGES, "*");
        config.setProperty(JsonDeserializer.VALUE_DEFAULT_TYPE, JsonNode.class.getName());

        Topology topology = CalculationsTopology.kafkaStreamTopology(MOCK_SCHEMA_REGISTRY_URL);
        logger.info(topology.describe().toString());
        testDriver = new TopologyTestDriver(topology, config);               

        avgOutputTopic = testDriver.createOutputTopic(
            "observations.weather.avg-air-temperature",
            stringSerde.deserializer(),
            aggrSerde.deserializer());

        processedInputTopic = testDriver.createInputTopic(
            "observations.weather.processed",
            stringSerde.serializer(),
            digitrafficSerde.serializer()); 
        
    }

    @AfterEach
    void afterEach() {        
        testDriver.close();
        MockSchemaRegistry.dropScope(SCHEMA_REGISTRY_SCOPE);
    }

    @Test
    public void shouldCalcAverage() throws IOException, RestClientException  {
        processedInputTopic.pipeInput("12016", DigitrafficMessage.newBuilder()
            .setId(1)
            .setRoadStationId(12016)
            .setName("ILMA")
            .setSensorValue(0.0f)
            .setSensorUnit("C")
            .setMeasuredTime(Instant.parse("2020-12-02T20:00:00Z").toEpochMilli()).build());

        processedInputTopic.pipeInput("12016", DigitrafficMessage.newBuilder()
            .setId(1)
            .setRoadStationId(12016)
            .setName("ILMA")
            .setSensorValue(1.0f)
            .setSensorUnit("C")
            .setMeasuredTime(Instant.parse("2020-12-02T20:59:00Z").toEpochMilli()).build());

        // one more event to move the streaming time outside grace period (10 minutes)
        processedInputTopic.pipeInput("12016", DigitrafficMessage.newBuilder()
            .setId(1)
            .setRoadStationId(12016)
            .setName("ILMA")
            .setSensorValue(2.0f)
            .setSensorUnit("C")
            .setMeasuredTime(Instant.parse("2020-12-02T21:11:00Z").toEpochMilli()).build());
            
        assertThat(avgOutputTopic.readKeyValue(), equalTo(new KeyValue<>("12016", 
            DigitrafficAggregate.newBuilder()
                .setId(1)
                .setRoadStationId(12016)
                .setName("ILMA")
                .setSensorValue(0.5f)            
                .setMeasuredTime(Instant.parse("2020-12-02T21:00:00Z").toEpochMilli()).build())));
        
    }    


}
