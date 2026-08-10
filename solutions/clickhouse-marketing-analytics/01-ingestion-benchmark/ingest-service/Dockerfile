# ingest-service container for Aiven Apps (or any same-region runtime).
# Build from the ingest-service/ directory:
#   docker build -t ingest-service .
# Run in REST mode against Aiven (benchmarks are then driven via the API):
#   docker run -p 8080:8080 --env-file ../.env.aiven \
#     -e SPRING_PROFILES_ACTIVE=aiven ingest-service

FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -q -B dependency:go-offline
COPY src ./src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build /build/target/ingest-service-*.jar app.jar
EXPOSE 8080
# No --tier: start in REST mode. POST /benchmarks triggers runs remotely;
# POST /events serves the mobile-fleet ingestion path; /actuator/health for probes.
ENTRYPOINT ["java", "-jar", "app.jar"]
