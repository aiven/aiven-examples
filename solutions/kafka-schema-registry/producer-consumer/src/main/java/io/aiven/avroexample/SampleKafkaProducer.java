package io.aiven.avroexample;

import io.aiven.avro.example.ClickRecord;
import io.confluent.kafka.serializers.KafkaAvroSerializer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringSerializer;

import java.io.BufferedReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;
import java.util.UUID;

import static io.aiven.avroexample.PropertiesInitialiser.initKafkaProperties;
import static io.aiven.avroexample.PropertiesInitialiser.readArg;

public final class SampleKafkaProducer {
    public static void main(String[] args) {
        private final static DEFAULT_FILENAME = "FileWithData.csv";
        final Properties props = initKafkaProducerProperties(args);
        String filename = readArg(args, "-f");
        Path filepath = filename == null ? Path.of(DEFAULT_FILENAME) : Path.of(filename);
        String topic = readArg(args, "-t");

        if (Files.notExists(filepath) || Files.isDirectory(filepath)) {
            throw new IllegalArgumentException("Please provide a valid filename with -f flag");
        }
        if (topic == null) {
            throw new IllegalArgumentException("Please provide a valid topic with -t flag");
        }
        try (KafkaProducer<String, ClickRecord> producer = new KafkaProducer<>(props);
            BufferedReader br = Files.newBufferedReader(filepath)) {
            String line;
            while ((line = br.readLine()) != null) {
                String[] fields = line.split(";");
                if (fields.length < 2) {
                    continue;
                }
                ClickRecord cr = new ClickRecord();
                cr.setSessionId(fields[0]);
                cr.setChannel(fields[1]);
                cr.setBrowser(fields.length > 2 ? fields[2] : null);
                cr.setCampaign(fields.length > 3 ? fields[3] : null);
                cr.setReferrer(fields.length > 4 ? fields[4] : null);
                cr.setIp(fields.length > 5 ? fields[5] : null);
                producer.send(new ProducerRecord<>(topic, "myKey_" + UUID.randomUUID(), cr));
            }
        } catch (Throwable ex) {
            ex.printStackTrace();
        }
    }

    private static Properties initKafkaProducerProperties(String[] args) {
        Properties props = initKafkaProperties(args);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, KafkaAvroSerializer.class.getName());
        return props;
    }
}
