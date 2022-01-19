package io.aiven.avroexample;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.common.config.SslConfigs;

import java.util.Locale;
import java.util.Properties;

class PropertiesInitialiser {
    static Properties initKafkaProperties(String[] args) {
        String bootstrapServers, truststore, keystorePassword, truststorePassword,
                keystore, schemaRegistryUrl, schemaRegistryUser, schemaRegistryPassword, sslKeyPassword;
        bootstrapServers = truststore = keystorePassword = truststorePassword = keystore =
                schemaRegistryUrl = schemaRegistryUser = schemaRegistryPassword = sslKeyPassword = null;
        for (int i = 0; i < args.length - 1; i++) {
            switch (args[i].toLowerCase(Locale.ROOT)) {
                case "-boostrap": case "-bs": bootstrapServers = args[++i]; break;
                case "-keystorepassword": case "-ksp": keystorePassword = args[++i]; break;
                case "-schemaregistryurl": case "-srurl": schemaRegistryUrl = args[++i]; break;
                case "-truststore": case "-ts": truststore = args[++i]; break;
                case "-truststorepassword": case "-tsp": truststorePassword = args[++i]; break;
                case "-keystore": case "-ks": keystore = args[++i]; break;
                case "-schemaregistrypassword": case "-srp": schemaRegistryPassword = args[++i]; break;
                case "-schemaregistryuser": case "-sru": schemaRegistryUser = args[++i]; break;
                case "-sslkeypassword": case "-sslp": sslKeyPassword = args[++i]; break;
            }
        }
        if (bootstrapServers == null || truststore == null || keystorePassword == null
          || truststorePassword == null || keystore == null || schemaRegistryUrl == null
          || schemaRegistryUser == null || schemaRegistryPassword == null || sslKeyPassword == null) {
            throw new IllegalArgumentException("One of bootstrapServers, truststore, keystorePassword, \n"
                    + "truststorePassword, keystore, schemaRegistryUrl, schemaRegistryUser, \n"
                    + "schemaRegistryPassword, sslKeyPassword is null");
        }
        final Properties props = new Properties();
        props.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
        props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, truststore);
        props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, truststorePassword);
        props.put(SslConfigs.SSL_KEYSTORE_TYPE_CONFIG, "PKCS12");
        props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, keystore);
        props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, keystorePassword);
        props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, sslKeyPassword);
        props.put("schema.registry.url", schemaRegistryUrl);
        props.put("basic.auth.credentials.source", "USER_INFO");
        props.put("basic.auth.user.info", schemaRegistryUser + ":" + schemaRegistryPassword);
        return props;
    }

    static String readArg(String[] args, String arg) {
        for (int i = 0; i < args.length - 1; i++) {
            if (arg.equalsIgnoreCase(args[i])) {
                return args[i + 1];
            }
        }
        return null;
    }
}
