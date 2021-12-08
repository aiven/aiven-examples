package io.aiven.streams;

import com.fasterxml.jackson.databind.JsonNode;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.Serdes;
import org.apache.kafka.streams.KafkaStreams;
import org.apache.kafka.streams.StreamsConfig;
import org.apache.kafka.streams.Topology;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.kafka.KafkaProperties;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerde;

import java.util.Properties;

@Configuration
public class KafkaStreamsConfig {
    @Autowired
    private ApplicationContext appContext;

    @Bean
    public KafkaStreams kafkaStreams(KafkaProperties kafkaProperties,
                                     @Value("${spring.application.name}") String appName) {
        final Properties props = new Properties();

        // inject SSL related properties
        props.putAll(kafkaProperties.getSsl().buildProperties());
        props.putAll(kafkaProperties.getProperties());
        
        // common client configurations
        props.put(CommonClientConfigs.CLIENT_DNS_LOOKUP_CONFIG, "use_all_dns_ips");        
        
        // stream config centric ones
        props.put(StreamsConfig.BOOTSTRAP_SERVERS_CONFIG, kafkaProperties.getBootstrapServers());        
        props.put(StreamsConfig.APPLICATION_ID_CONFIG, appName);
        props.put(StreamsConfig.DEFAULT_KEY_SERDE_CLASS_CONFIG, Serdes.String().getClass());
        props.put(StreamsConfig.DEFAULT_VALUE_SERDE_CLASS_CONFIG, JsonSerde.class);
        props.put(StreamsConfig.STATE_DIR_CONFIG, "data");

        // producer config        
        props.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "gzip");
        props.put(ProducerConfig.RETRIES_CONFIG, "3");
        // others
        props.put(JsonDeserializer.VALUE_DEFAULT_TYPE, JsonNode.class);
        
        final KafkaStreams kafkaStreams = new KafkaStreams((Topology) appContext.getBean("kafkaStreamTopology"), props);

        kafkaStreams.start();

        return kafkaStreams;
    }

}