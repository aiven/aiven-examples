import com.github.davidmc24.gradle.plugin.avro.GenerateAvroJavaTask

val junit_version: String by project
val logback_version: String by project
val parallel_consumer_version: String by project
val avro_version: String by project
val kafka_avro_version: String by project

plugins {
    id("java")
    id("com.github.davidmc24.gradle.plugin.avro") version "1.5.0"
}

group = "io.aiven"
version = "0.1.0"

repositories {
    mavenCentral()
    gradlePluginPortal()
    maven {
        url = uri("https://packages.confluent.io/maven/")
    }
}

dependencies {
    implementation("io.confluent.parallelconsumer:parallel-consumer-core:$parallel_consumer_version")
    implementation("ch.qos.logback:logback-classic:$logback_version")

    implementation("io.confluent:kafka-avro-serializer:$kafka_avro_version") {
        exclude(group = "org.apache.kafka") // has conflicts with the parallel consumer
    }

    implementation("org.apache.avro:avro:$avro_version")
    testImplementation("org.junit.jupiter:junit-jupiter-api:$junit_version")
    testRuntimeOnly("org.junit.jupiter:junit-jupiter-engine:$junit_version")
}

tasks.getByName<Test>("test") {
    useJUnitPlatform()
}

tasks.getByName<GenerateAvroJavaTask>("generateAvroJava") {
    source("src/main/avro")
    setOutputDir(file("src/main/java"))
}

tasks.jar {
    from(
        configurations.runtimeClasspath.get().map { if (it.isDirectory) it else zipTree(it) }
    )
    duplicatesStrategy = DuplicatesStrategy.INCLUDE
}