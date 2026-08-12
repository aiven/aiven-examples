# ingest-service + loadgen-service in ONE container, for Aiven Apps.
#
# Why: Aiven Apps deploys each compose service as its own app - there is no
# shared container network, so loadgen can only reach ingest through the
# public *.aiven.app ingress, whose h2 connection rotation caps single-event
# load at ~3.5k req/s regardless of server capacity (see BENCHMARK-RESULTS.md).
# Colocating both JVMs puts the load path on localhost: no TLS, no proxy, no
# GOAWAY churn - the run measures the receiver itself.
#
# Tradeoff to keep in mind when reading numbers: sender and receiver now share
# the container's vCPUs, so this measures "service capacity minus loadgen CPU",
# the mirror image of the through-ingress runs.
#
# Build context is the solution root (clickhouse-marketing-analytics/):
#   docker build -f deploy/aiven-apps/combined/Dockerfile -t bench-combined .

FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /build
COPY 01-ingestion-benchmark/ingest-service/pom.xml ingest/pom.xml
COPY shared/loadgen-service/pom.xml loadgen/pom.xml
RUN mvn -q -B -f ingest/pom.xml dependency:go-offline \
 && mvn -q -B -f loadgen/pom.xml dependency:go-offline
COPY 01-ingestion-benchmark/ingest-service/src ingest/src
COPY shared/loadgen-service/src loadgen/src
RUN mvn -q -B -f ingest/pom.xml -DskipTests package \
 && mvn -q -B -f loadgen/pom.xml -DskipTests package

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build /build/ingest/target/ingest-service-*.jar ingest.jar
COPY --from=build /build/loadgen/target/loadgen-service-*.jar loadgen.jar
COPY deploy/aiven-apps/combined/entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
# 8080 = ingest control plane (/benchmarks, /config, /stats, /events)
# 8090 = loadgen control plane (/loadtests)
EXPOSE 8080 8090
ENTRYPOINT ["/app/entrypoint.sh"]
