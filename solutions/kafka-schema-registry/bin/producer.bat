@echo off
java -cp "%~dp0\..\producer-consumer\target\*" io.aiven.avroexample.SampleKafkaProducer %*
