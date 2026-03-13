# Cluster throughput discovery — run in a container against an external Kafka cluster.
FROM apache/kafka:3.7.0

USER root

COPY cluster-throughput-discovery.sh /opt/kafka/
RUN chmod +x /opt/kafka/cluster-throughput-discovery.sh && chown appuser:appuser /opt/kafka/cluster-throughput-discovery.sh

ENV OUTPUT_DIR=/output
ENV KAFKA_OPTS="-Xmx512m"
RUN mkdir -p /output && chown appuser:appuser /output

USER appuser
WORKDIR /opt/kafka

ENTRYPOINT ["/bin/bash", "-c"]
CMD ["./cluster-throughput-discovery.sh"]
