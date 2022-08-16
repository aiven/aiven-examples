/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.example;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.base.DeliveryGuarantee;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.connector.kafka.source.enumerator.initializer.OffsetsInitializer;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

import java.util.Properties;

/**
 * An example Apache Flink® job that connects to
 * <a href="https://developer.aiven.io/docs/products/kafka/howto/flink-with-aiven-for-kafka">Aiven
 * for Apache Kafka®</a>.
 */
public class DataStreamJob {


    public static void main(String[] args) throws Exception {
        // Sets up the execution environment, which is the main entry point
        // to building Flink applications.
        final StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        Properties props = new Properties();
        props.put("security.protocol", "SSL");
        props.put("ssl.endpoint.identification.algorithm", "");
        props.put("ssl.truststore.location", "TRUSTSTORE_PATH/client.truststore.jks");
        props.put("ssl.truststore.password", "KEY_TRUST_SECRET");
        props.put("ssl.keystore.type", "PKCS12");
        props.put("ssl.keystore.location", "KEYSTORE_PATH/client.keystore.p12");
        props.put("ssl.keystore.password", "KEY_TRUST_SECRET");
        props.put("ssl.key.password", "KEY_TRUST_SECRET");

        KafkaSource<String> source = KafkaSource.<String>builder()
                .setBootstrapServers("APACHE_KAFKA_HOST:APACHE_KAFKA_PORT")
                .setGroupId("test-flink-input-group")
                .setTopics("test-flink-input")
                .setProperties(props)
                .setStartingOffsets(OffsetsInitializer.earliest())
                .setValueOnlyDeserializer(new SimpleStringSchema())
                .build();

        KafkaSink<String> sink = KafkaSink.<String>builder()
                .setBootstrapServers("APACHE_KAFKA_HOST:APACHE_KAFKA_PORT")
                .setKafkaProducerConfig(props)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic("test-flink-output")
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build()
                )
                .setDeliverGuarantee(DeliveryGuarantee.AT_LEAST_ONCE)
                .build();

        // ... processing continues here
        env
                .fromSource(source, WatermarkStrategy.noWatermarks(), "Kafka Source")
                .map(new StringCapitalizer())
                .sinkTo(sink);
        env.execute("Flink Java capitalizer");
    }
}
