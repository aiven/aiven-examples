# Build:
#   docker build -t loadgen-service .
# Run (local):
#   docker run --rm -p 8090:8090 -e TARGET_URL=http://host.docker.internal:8080 loadgen-service
# POST /loadtests drives it; /actuator/health for probes.

FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:25-jre
WORKDIR /app
COPY --from=build /build/target/loadgen-service-*.jar app.jar
EXPOSE 8090
ENTRYPOINT ["java", "-jar", "app.jar"]
