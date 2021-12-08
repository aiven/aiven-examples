# Kafka Streams Example

This example shows how you can implement different stream processing capabilities using Java and Kafka Streams SDK. Implementation is using Spring Profiles to define which stream processing topology is being used. There are three example topologies on this demo:

## EnrichmentTopology

Enrich message by utilizing KStream - KTable joins. KTable holds the metadata for weather stations sourced from PostgreSQL table. KStream is the weather observation stream ingested from MQTT broker.

## CalculationsTopology

Calculate 1 hour tumbling average air temperature for each weather station.

## CreateMultivariate

Use Session Windowing to create multi variate observation from single variate observations. This type of time series structure will match the dataset we are using for training the forecast model.
