# M3DB Sink

This is a small Python Kafka Consumer which will consume messages from Kafka and build InfluxDB Line Format payloads. Payload batch is then sent to M3DB InfluxDB compatible HTTP endpoint.