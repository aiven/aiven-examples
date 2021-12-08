FROM adoptopenjdk/openjdk14:x86_64-alpine-jre-14.0.2_12
# copy the packaged jar file into our docker image
COPY build/libs/streams-0.4.4-SNAPSHOT.jar /demo.jar
COPY jmx-config/kafka-client.yaml /kafka-client.yaml
ADD https://repo1.maven.org/maven2/io/prometheus/jmx/jmx_prometheus_javaagent/0.16.1/jmx_prometheus_javaagent-0.16.1.jar /

# set the startup command to execute the jar
#CMD ["java", "-jar", "/demo.jar"]
ENTRYPOINT exec java $JAVA_OPTS -jar /demo.jar
