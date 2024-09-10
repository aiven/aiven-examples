# Mirrormaker 2 Consumer Groups and Offset sync Validation tool guide

Goal/Outcome : Offset sync tool inspects source and target cluster and compares the consumer group states. The tool emits the result as CSV.

## Prerequisites

Before starting the migration, ensure the following:

- A Linux machine with network access to both Strimzi and Aiven for Kafka services
- Java JDK and JRE 17 (OpenJDK 17) -- 
  - Can be downloaded using standard Linux APT commands
  - ```bash
    sudo apt install openjdk-17-jre-headless
    sudo apt install openjdk-17-jdk-headless
    java -version
  ```
- Latest version of Gradle compatible to compile Java 17 program
- Aiven CLI/API access 
- A valid Aiven User Token via Aiven CLI, Reference : https://aiven.io/docs/tools/cli/user/user-access-token#avn-user-access-token-create
- A running Aiven Kafka and Strimzi Cluster
- Aiven Kafka SSL integration certificates
  - Client Truststore JKS
  - Client Keystore p12
  - SSL Keystore and Truststore password
  - These can be downloaded via Aiven CLI, Reference : https://aiven.io/docs/tools/cli/service/user#avn_service_user_kafka_java_creds

## HOW TO
### Create the Utility and Kafka release tarball
#### STEP-1 Clone the Kafka fork:
```bash
$ git clone -b jjaakola-aiven-add-mm2-offset-inspector-tool --single-branch git@github.com:jjaakola-aiven/kafka.git
```
The tool/utility is located in the full Kafka distribution and must be compiled, and a release tarball shall be created once:

```bash
$ ./gradlew --no-daemon releaseTarGz
```
The Release tarball is in Directory : ```./core/build/distributions/kafka_2.13-4.0.0-SNAPSHOT.tgz```

## RUN THE TOOL
Consumer Groups and Offset sync validation tool requires the Mirrormaker 2 properties file. This ensures that the actual configuration of the clusters and replication flows are inspected.

### Dependency 
Please gather the required configurations from your Aiven MM2, Kafka and Strimzi services configurations to prepare the configuration template file. 

MM2 Configuration Template file example
```properties
emit.checkpoints.enabled=True
emit.checkpoints.interval.seconds=10
offset.lag.max=1
refresh.groups.enabled=True
refresh.groups.interval.seconds=180
refresh.topics.enabled=True
refresh.topics.interval.seconds=60
sync.group.offsets.enabled=True
sync.group.offsets.interval.seconds=10
sync.topic.configs.enabled=True
tasks.max=192
aiven-destination-kafka-name.bootstrap.servers=<DESTINATION-BOOTSTRAP-SERVERS>
aiven-destination-kafka-name.security.protocol=PLAINTEXT
aiven-destination-kafka-name.producer.batch.size=32768
aiven-destination-kafka-name.producer.buffer.memory=33554432
aiven-destination-kafka-name.producer.linger.ms=100
aiven-destination-kafka-name.producer.max.request.size=66901452
source-kafka-name.bootstrap.servers=<SOURCE-BOOTSTRAP-SERVERS>
source-kafka-name.security.protocol=PLAINTEXT
source-kafka-name.consumer.max.poll.records=1000
clusters=aiven-destination-kafka-name, source-kafka-name
source-kafka-name->aiven-destination-kafka-name.enabled=True
source-kafka-name->aiven-destination-kafka-name.config.properties.exclude=follower\\.replication\\.throttled\\.replicas, leader\\.replication\\.throttled\\.replicas, message\\.timestamp\\.difference\\.max\\.ms, message\\.timestamp\\.type, unclean\\.leader\\.election\\.enable
source-kafka-name->aiven-destination-kafka-name.emit.heartbeats.enabled=True
source-kafka-name->aiven-destination-kafka-name.offset-syncs.topic.location=target
source-kafka-name->aiven-destination-kafka-name.replication.factor=2
source-kafka-name->aiven-destination-kafka-name.replication.policy.class=org.apache.kafka.connect.mirror.IdentityReplicationPolicy
source-kafka-name->aiven-destination-kafka-name.sync.group.offsets.enabled=True
source-kafka-name->aiven-destination-kafka-name.sync.group.offsets.interval.seconds=1
source-kafka-name->aiven-destination-kafka-name.topics=<TOPIC LIST, COMMA SEPARATED>
source-kafka-name->aiven-destination-kafka-name.topics.blacklist=.*[\\-\\.]internal, .*\\.replica, __.*, connect.*
sync.topic.acls.enabled=False
mm.enable.internal.rest=True
dedicated.mode.enable.internal.rest=True
listeners=http\://localhost\:26084
admin.timeout.ms=1800000
aiven-destination-kafka-name.ssl.truststore.location=<TRUSTSTORE PATH>
aiven-destination-kafka-name.ssl.truststore.password=<TRUSTSTORE PASSWORD>
aiven-destination-kafka-name.ssl.keystore.type=<KEYSTORE TYPE, PKCS12|JKS>
aiven-destination-kafka-name.ssl.keystore.location=<KEYSTORE PATH>
aiven-destination-kafka-name.ssl.keystore.password=<KEYSTORE PASSWORD>
aiven-destination-kafka-name.ssl.key.password=<KEY_PASSWORD>
```

### TOOL USAGE GUIDE
```bash
$ ./bin/kafka-mirrormaker-offset-sync-inspector.sh --help
usage: mirror-maker-consumer-group-offset-sync-inspector
       [-h] --mm2-config mm2.properties [--output-path OUTPUT_PATH] [--admin-timeout ADMIN_TIMEOUT] [--request-timeout REQUEST_TIMEOUT] [--include-inactive-groups] [--include-ok-groups]

MirrorMaker 2.0 consumer group offset sync inspector

optional arguments:
  -h, --help             show this help message and exit
  --mm2-config mm2.properties
                         MM2 configuration file.
  --output-path OUTPUT_PATH
                         The result CSV file output path. If not given the result is printed to the console.
  --admin-timeout ADMIN_TIMEOUT
                         Kafka API operation timeout in ISO duration format. Defaults to PT1M.
  --request-timeout REQUEST_TIMEOUT
                         Kafka API requests timeout in ISO duration format. Defaults to PT30S.
  --include-inactive-groups
                         Inspect also inactive (empty/dead) consumer groups.
  --include-ok-groups    Emit consumer group inspection results for groups that are ok.

```

[NOTE]
By default the tool filters out all inactive and groups that have synced ok. The following command gives the default output. On the BMC cluster high timeout values are required.

```bash
$ ./bin/kafka-mirrormaker-offset-sync-inspector.sh --mm2-config <CONFIG FILE PATH> --admin-timeout PT10M –request-timeout PT60S.
```
[NOTE]

### CSV File Format
Format is subject to change during development. File contains the following headers and columns.

- CLUSTER PAIR
  - The replication flow. 
  - source->target
- GROUP 
  - Consumer group name.
- GROUP STATE 
  - Consumer group state.
- TOPIC 
  - The topic name.
- PARTITION 
  - The topic partition.
- SOURCE OFFSET 
  - Consumer group committed offset at the source.
- TARGET LAG TO SOURCE 
  - Lag of the consumer group compared to the latest offset at the source.
- TARGET OFFSET 
  - Consumer group synced offset at the target. This is the translated offset.
- TARGET LAG 
  - Consumer group lag at the target cluster.
- IS OK 
  - Tool's indication of the offset sync state. When false the consumer group and topic partition manual requires investigation.
- MESSAGE 
  - Message/Reason why the result is _true or false_.

#### MESSAGE Definitions
- Message : _**“Target has offset sync.”**_
  - The state of syncing is ok. 
  - Target cluster consumer group has an offset synced for the topic partition.
- Message **_“Source partition is empty therefore offset not expected to be synced.”_**
  - The state of syncing is ok. 
  - Target cluster consumer group does not have offset as source partition is empty.
- Message **_“Source partition not empty therefore offset expected to be synced.”_**
  - The state of syncing is false. 
  - Target cluster consumer group does not have offset but source partition has data. 
- Message : **_“Target consumer group missing the topic partition. Source partition is empty therefore offset not expected to be synced.”_**
  - The state of syncing is ok. 
  - Consumer group is missing from the target and the source partition does not have data.
- Message **_“Target consumer group missing the topic partition. Source partition not empty therefore offset expected to be synced.”
  The state of syncing is false._**
  - Consumer group is missing from the target and the source partition has data. 
  - If the consumer group state is "Empty", this is likely a false positive but requires manual checking.
- Message : **_“Target missing the consumer group.”_**
  - The state of syncing is false. 
  - Consumer group is missing from the target. 
  - Requires manual checking.
















