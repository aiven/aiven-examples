package io.aiven.heartbeat;

import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.connect.mirror.Heartbeat;

import java.util.Collections;
import java.util.Properties;
import java.time.Duration;

public class App {
    public static void main( String[] args )
    {
        Properties props = new Properties();
        props.put("bootstrap.servers", "mykafka.aivencloud.com:18300"); // CHANGE BASED ON YOUR SETUP
        props.put("group.id", "heartbeats-monitor"); // CHANGE BASED ON YOUR SETUP
        props.put("enable.auto.commit", "false"); // CHANGE BASED ON YOUR SETUP
        props.put("auto.offset.reset", "earliest");
        props.put("security.protocol", "SSL");
        props.put("ssl.truststore.location", "certs/client.truststore.jks"); // CHANGE BASED ON YOUR SETUP
        props.put("ssl.truststore.password", "VERYSECRETPASSWORD"); // CHANGE BASED ON YOUR SETUP
        props.put("ssl.keystore.type", "PKCS12");
        props.put("ssl.keystore.location", "certs/client.keystore.p12"); // CHANGE BASED ON YOUR SETUP
        props.put("ssl.keystore.password", "VERYSECRETPASSWORD"); // CHANGE BASED ON YOUR SETUP
        props.put("ssl.key.password", "VERYSECRETPASSWORD"); // CHANGE BASED ON YOUR SETUP
        props.put("key.deserializer", "org.apache.kafka.common.serialization.ByteArrayDeserializer");
        props.put("value.deserializer", "org.apache.kafka.common.serialization.ByteArrayDeserializer");

        KafkaConsumer<byte[], byte[]> consumer = new KafkaConsumer<byte[], byte[]>(props);
        consumer.subscribe(Collections.singletonList("heartbeats")); // CHANGE BASED ON YOUR SETUP

        int cnt = 0;
        while (true) {
            final ConsumerRecords<byte[], byte[]> consumerRecords =
                    consumer.poll(Duration.ofSeconds(10));

            cnt += consumerRecords.count();
            if (consumerRecords.count()==0) {
                continue;
            }

            consumerRecords.forEach(record -> {
                Heartbeat hb = Heartbeat.deserializeRecord(record);
                System.out.printf("Heartbeat Record: %d | %s -> %s \n", hb.timestamp(), hb.sourceClusterAlias(), hb.targetClusterAlias());
            });

            if (cnt > 10) {
                break;
            }
        }
        consumer.close();
    }
}

/* SAMPLE OUTPUT
Heartbeat Record: 1637191705472 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191706472 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191707472 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191708473 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191709473 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191710473 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191711473 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191712474 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191713474 | kafka-primary -> kafka-secondary 
Heartbeat Record: 1637191714474 | kafka-primary -> kafka-secondary 
*/