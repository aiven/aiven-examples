package io.aiven.config;

import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.BytesDeserializer;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

import java.util.Properties;

public class AppConfig {
    private static final String ROOT_PATH           = System.getProperty("user.home", ".");
    public static String BOOTSTRAP_SERVERS          = "";
    public static String SCHEMA_REGISTRY_URL        = "";
    public static String CREDENTIALS_SOURCE         = "USER_INFO";
    public static String AUTH_USER_INFO             = "";
    public static String TEST_TOPIC                 = "test.parallel.partitioned";
    public static String CREDENTIALS_PATH           = ROOT_PATH + "/Documents/temp/credentials";


    public static int totalConsumerThreads  = 3;
    public static int messagesPerSecond     = 16;
    public static int totalMessagesToSent   = 10000;
    public static int keyspaceSizeUpper     = 100;
    public static int payloadSize           = 400;

    public static Properties getProducerProps() {
        var properties = new Properties();
        properties.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
        properties.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getCanonicalName());
        properties.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class.getCanonicalName());
        properties.put(ProducerConfig.ACKS_CONFIG, "1");
        return setRegistryConfig(setSecurityConfig(properties));
    }

    public static Properties getConsumerProps() {
        var properties = new Properties();
        properties.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG,  AppConfig.BOOTSTRAP_SERVERS);
        properties.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG,  StringDeserializer.class.getCanonicalName());
        properties.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,  KafkaAvroDeserializer.class.getCanonicalName());
        properties.put(ConsumerConfig.GROUP_ID_CONFIG, "parallel-group-0");
        properties.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "latest");
        properties.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        return setRegistryConfig(setSecurityConfig(properties));
    }

    public static Properties setSecurityConfig(Properties properties) {
        properties.put("security.protocol", "SSL");
        properties.put("ssl.truststore.location", AppConfig.CREDENTIALS_PATH + "/client.truststore.jks");
        properties.put("ssl.truststore.password", "pass123");
        properties.put("ssl.keystore.type", "PKCS12");
        properties.put("ssl.keystore.location", AppConfig.CREDENTIALS_PATH + "/client.keystore.p12");
        properties.put("ssl.keystore.password", "pass123");
        properties.put("ssl.key.password", "pass123");
        return properties;
    }

    public static Properties setRegistryConfig(Properties properties) {
        properties.put("schema.registry.url", SCHEMA_REGISTRY_URL);
        properties.put("basic.auth.credentials.source", CREDENTIALS_SOURCE);
        properties.put("basic.auth.user.info",  AUTH_USER_INFO);
        return properties;
    }
}
