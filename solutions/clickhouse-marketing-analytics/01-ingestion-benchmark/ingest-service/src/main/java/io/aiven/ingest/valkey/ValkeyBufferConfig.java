package io.aiven.ingest.valkey;

import io.lettuce.core.RedisClient;
import io.lettuce.core.api.StatefulRedisConnection;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Wiring for the Valkey Streams buffer (ingest.buffer=valkey). One shared
 * connection serves the producer path (XADD is sub-ms and pipelined by
 * Lettuce) and the config store; the flusher opens its own connection because
 * XREADGROUP BLOCK parks the connection it runs on.
 */
@Configuration
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class ValkeyBufferConfig {

    @Bean(destroyMethod = "shutdown")
    public RedisClient valkeyClient(ValkeyProperties props) {
        return RedisClient.create(props.lettuceUri());
    }

    @Bean(destroyMethod = "close")
    public StatefulRedisConnection<String, String> valkeyConnection(RedisClient client) {
        return client.connect();
    }
}
