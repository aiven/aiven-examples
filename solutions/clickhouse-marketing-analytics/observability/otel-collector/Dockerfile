# OTel Collector for Aiven Apps (or any same-region runtime).
#   docker build -t otel-collector-bench .
#   docker run -p 4318:4318 -e THANOS_REMOTE_WRITE_URI=... \
#     -e THANOS_USER=... -e THANOS_PASSWORD=... otel-collector-bench
# Health probe: :13133

FROM otel/opentelemetry-collector-contrib:latest
COPY config.yaml /etc/otelcol-contrib/config.yaml
EXPOSE 4317 4318 13133
