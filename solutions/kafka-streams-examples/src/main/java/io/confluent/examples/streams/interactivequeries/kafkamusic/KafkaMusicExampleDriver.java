/*
 * Copyright Confluent Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.confluent.examples.streams.interactivequeries.kafkamusic;

import io.confluent.examples.streams.avro.PlayEvent;
import io.confluent.examples.streams.avro.Song;
import io.confluent.kafka.serializers.AbstractKafkaSchemaSerDeConfig;
import io.confluent.kafka.streams.serdes.avro.SpecificAvroSerializer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.LongSerializer;
import org.apache.kafka.common.serialization.Serdes;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Random;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import static java.nio.charset.StandardCharsets.UTF_8;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.common.config.SslConfigs;
import java.util.HashMap;

/**
 * This is a sample driver for the {@link KafkaMusicExample}.
 * To run this driver please first refer to the instructions in {@link KafkaMusicExample}.
 * You can then run this class directly in your IDE or via the command line.
 *
 * To run via the command line you might want to package as a fatjar first. Please refer to:
 * <a href='https://github.com/confluentinc/kafka-streams-examples#packaging-and-running'>Packaging</a>
 *
 * Once packaged you can then run:
 * <pre>
 * {@code
 * $ java -cp target/kafka-streams-examples-7.1.1-standalone.jar \
 *      io.confluent.examples.streams.interactivequeries.kafkamusic.KafkaMusicExampleDriver
 * }
 * </pre>
 * You should terminate with Ctrl-C
 */
public class KafkaMusicExampleDriver {

  /**
   * TODO -After the KafkaMusicExampleDriver class declaration add the following two lines
   * TODO -to set the DEFAULT_BOOTSTRAP_SERVERS and DEFAULT_SCHEMA_REGISTRY_URL endpoints
   * TODO -replacing the APACHE_KAFKA_HOST, APACHE_KAFKA_PORT, APACHE_KAFKA_HOST, SCHEMA_REGISTRY_PORT
   * TODO -placeholders
   */
  private static final String DEFAULT_BOOTSTRAP_SERVERS = "YOUR_AIVEN_KAFKA_PUBLIC_URL:KAFKA_PORT";
  private static final String DEFAULT_SCHEMA_REGISTRY_URL = "https://YOUR_AIVEN_KAFKA_PUBLIC_URL:YOUR_SCHEMA_REGISTRY_PORT";
  private static final String TRUST_STORE_PASSWORD ="YOUR_LOCAL_TRUST_STORE_PASSWORD";

  private static final String KEY_STORE_PASSWORD ="YOUR_LOCAL_KEY_STORE_PASSWORD";

  public static void main(final String [] args) throws Exception {
    //final String bootstrapServers = args.length > 0 ? args[0] : "localhost:9092";
    //final String schemaRegistryUrl = args.length > 1 ? args[1] : "http://localhost:8081";
    final String bootstrapServers = args.length > 1 ? args[1] : DEFAULT_BOOTSTRAP_SERVERS;
    final String schemaRegistryUrl = args.length > 2 ? args[2] : DEFAULT_SCHEMA_REGISTRY_URL;
    System.out.println("Connecting to Kafka cluster via bootstrap servers " + bootstrapServers);
    System.out.println("Connecting to Confluent schema registry at " + schemaRegistryUrl);

    // Read comma-delimited file of songs into Array
    final List<Song> songs = new ArrayList<>();
    final String SONGFILENAME= "song_source.csv";
    final InputStream inputStream = KafkaMusicExample.class.getClassLoader().getResourceAsStream(SONGFILENAME);
    final InputStreamReader streamReader = new InputStreamReader(inputStream, UTF_8);
    try (final BufferedReader br = new BufferedReader(streamReader)) {
      String line = null;
      while ((line = br.readLine()) != null) {
        final String[] values = line.split(",");
        final Song newSong = new Song(Long.parseLong(values[0]), values[1], values[2], values[3], values[4]);
        songs.add(newSong);
      }
    }
    System.out.println("size of the list to publish:"+songs.size());
    final Properties props = new Properties();
    props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);

    /**
     * TODO -define the keystore and truststore location and secrets for SSL connection,
     * TODO -by replacing the placeholders KEYSTORE_PATH, TRUSTSTORE_PATH and KEY_TRUST_SECRET
     * TODO -with the values set when creating the keystore and truststore.
     */
    props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
    props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "PATH_TO_YOUR/client.truststore.jks");
    props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, TRUST_STORE_PASSWORD);
    props.put(SslConfigs.SSL_KEYSTORE_TYPE_CONFIG, "PKCS12");
    props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, "PATH_TO_YOUR/client.keystore.p12");
    props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, KEY_STORE_PASSWORD);
    props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG,KEY_STORE_PASSWORD);


    /**
     * TODO -passing the schema registry username and password and
     * TODO -substituting the SCHEMA_REGISTRY_USER and SCHEMA_REGISTRY_PASSWORD placeholders
     */
    final Map<String, String> serdeConfig = new HashMap<>();
    serdeConfig.put(AbstractKafkaSchemaSerDeConfig.SCHEMA_REGISTRY_URL_CONFIG, schemaRegistryUrl);
    serdeConfig.put(AbstractKafkaSchemaSerDeConfig.BASIC_AUTH_CREDENTIALS_SOURCE, "USER_INFO");
    serdeConfig.put(AbstractKafkaSchemaSerDeConfig.USER_INFO_CONFIG, "avnadmin:AVNS_luJOlps0dm4EvygULIb");

    final SpecificAvroSerializer<PlayEvent> playEventSerializer = new SpecificAvroSerializer<>();
    playEventSerializer.configure(serdeConfig, false);
    final SpecificAvroSerializer<Song> songSerializer = new SpecificAvroSerializer<>();
    songSerializer.configure(serdeConfig, false);

    final KafkaProducer<String, PlayEvent> playEventProducer = new KafkaProducer<>(props,
                                                                                   Serdes.String().serializer(),
                                                                                   playEventSerializer);

    final KafkaProducer<Long, Song> songProducer = new KafkaProducer<>(props,
                                                                       new LongSerializer(),
                                                                       songSerializer);

    songs.forEach(song -> {
      System.out.println("Writing song information for '" + song.getName() + "' to input topic " +
          KafkaMusicExample.SONG_FEED);
      //ProducerRecord record = new ProducerRecord<>(KafkaMusicExample.SONG_FEED, song.getId(), song);
      //System.out.println("record value:  "+record.value());
      songProducer.send(new ProducerRecord<>(KafkaMusicExample.SONG_FEED, song.getId(), song));
    });

    songProducer.close();
    final long duration = 60 * 1000L;
    final Random random = new Random();

    // send a play event every 100 milliseconds
    while (true) {
      final Song song = songs.get(random.nextInt(songs.size()));
      System.out.println("Writing play event for song " + song.getName() + " to input topic " +
          KafkaMusicExample.PLAY_EVENTS);
      playEventProducer.send(
          new ProducerRecord<>(KafkaMusicExample.PLAY_EVENTS,
                                                "uk", new PlayEvent(song.getId(), duration)));
      Thread.sleep(100L);
    }
  }

}
