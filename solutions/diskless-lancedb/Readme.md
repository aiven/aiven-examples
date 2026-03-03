# Kafka Diskless Topics to LanceDB Integration

This example demonstrates how to produce messages to Aiven Kafka Diskless topics and consume them into LanceDB for vector storage and search capabilities.

## Overview

The solution consists of:
- **Producer**: Produces messages to Aiven Kafka Diskless topics with optimized settings
- **Consumer**: Consumes messages from Kafka Diskless topics and writes them to LanceDB
- **LanceDB Integration**: Stores Kafka messages as vectors in LanceDB for efficient similarity search

## Architecture

```
Kafka Producer → Aiven Kafka Diskless Topic → Kafka Consumer → LanceDB
```

## Prerequisites

1. **Aiven Account**: An active Aiven account with a Kafka service
2. **Kafka Diskless Topic**: A Kafka topic configured with diskless storage enabled
3. **Python 3.8+**: Python runtime environment
4. **Kafka Certificates**: SSL certificates for connecting to Aiven Kafka

## Setup

### 1. Install Dependencies

Create a virtual environment and install required packages:

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Configure Aiven Kafka Service

If you don't have a Kafka service with diskless topics, you can use the [diskless-foundation-setup](../diskless-foundation-setup/) Terraform configuration to create one.

#### Create Kafka Service and Topic

```bash
# Set your Aiven project and service details
export PROJECT_NAME=your-project-name
export SERVICE_NAME=your-kafka-service
export CLOUD=google-europe-west1
export PLAN=business-16-inkless

# Create a diskless topic
avn service topic-create \
  --project $PROJECT_NAME \
  --partitions 3 \
  --replication 1 \
  $SERVICE_NAME \
  diskless-topic

# Enable diskless storage on the topic
avn service topic-update \
  --project $PROJECT_NAME \
  -c '{"diskless_enable": true}' \
  $SERVICE_NAME \
  diskless-topic
```

#### Download Kafka Certificates

```bash
# Create certs directory
mkdir -p certs

# Download certificates for avnadmin user
avn service user-kafka-java-creds \
  --project $PROJECT_NAME \
  --username avnadmin \
  $SERVICE_NAME \
  --target-directory ./certs

# Or download for a specific user
avn service user-create \
  --project $PROJECT_NAME \
  --username kafka-user \
  $SERVICE_NAME

avn service user-creds-download \
  --project $PROJECT_NAME \
  --username kafka-user \
  --target-directory ./certs \
  $SERVICE_NAME
```

#### Get Bootstrap Servers

```bash
export BOOTSTRAP_SERVER=$(avn service get --format '{service_uri}' $SERVICE_NAME --project $PROJECT_NAME)
echo "Bootstrap Server: $BOOTSTRAP_SERVER"
```

### 3. Configure Environment Variables

Copy the example configuration and set your values:

```bash
cp config.example .env
```

Edit `.env` with your configuration:

```bash
# Aiven Kafka Configuration
KAFKA_BOOTSTRAP_SERVERS=your-kafka-service.aivencloud.com:24949
KAFKA_CERT_FOLDER=./certs
KAFKA_TOPIC_NAME=diskless-topic
KAFKA_GROUP_ID=lancedb-consumer-group
KAFKA_RACK=rack-1  # Optional: for AZ-aware clients

# Producer Configuration
NUM_MESSAGES=10
MESSAGE_DELAY=1.0

# Consumer & LanceDB Configuration
BATCH_SIZE=100
VECTOR_DIM=128
LANCEDB_PATH=./lancedb_data
LANCEDB_TABLE_NAME=kafka_messages
```

Or export them directly:

```bash
export KAFKA_BOOTSTRAP_SERVERS="your-kafka-service.aivencloud.com:24949"
export KAFKA_CERT_FOLDER="./certs"
export KAFKA_TOPIC_NAME="diskless-topic"
export KAFKA_GROUP_ID="lancedb-consumer-group"
export LANCEDB_PATH="./lancedb_data"
export LANCEDB_TABLE_NAME="kafka_messages"
```

## Usage

### Running the Producer

Produce messages to the Kafka Diskless topic:

```bash
python kafka_producer.py
```

The producer will:
- Connect to Aiven Kafka using SSL certificates
- Produce sample messages with optimized settings for diskless storage
- Use batching and compression for efficiency

**Producer Optimizations for Diskless:**
- `linger_ms=100`: Wait up to 100ms to batch messages
- `batch_size=16384`: 16KiB batch size
- `max_request_size=1048576`: 1MiB max request size
- `acks=all`: Wait for all replicas
- `enable_idempotence=true`: Exactly-once semantics
- `max_in_flight_requests_per_connection=2`: Reduced from default 5

### Running the Consumer

Consume messages and write to LanceDB:

```bash
python kafka_consumer_lancedb.py
```

The consumer will:
- Connect to Aiven Kafka using SSL certificates
- Consume messages from the diskless topic
- Create vector representations of messages
- Batch messages and write them to LanceDB
- Store metadata including Kafka offsets, partitions, and timestamps

**Consumer Optimizations for Diskless:**
- `fetch_max_bytes=1048576`: 1MiB fetch size
- `max_partition_fetch_bytes=1048576`: 1MiB per partition
- `fetch_min_bytes=1`: Minimum bytes to fetch
- `fetch_max_wait_ms=500`: Maximum wait time

### Querying LanceDB

After consuming messages, you can query LanceDB:

```python
import lancedb

# Connect to LanceDB
db = lancedb.connect("./lancedb_data")
table = db.open_table("kafka_messages")

# Perform vector search
query_vector = [0.1] * 128  # Your query vector
results = table.search(query_vector).limit(10).to_pandas()
print(results)

# Filter by metadata
results = table.search(query_vector).where("category = 'category_0'").limit(10).to_pandas()
print(results)
```

## Vector Generation

The current implementation uses a simple hash-based vector generation method. For production use, you should:

1. **Use Proper Embeddings**: Replace the hash-based vector generation with proper embeddings using libraries like:
   - `sentence-transformers` for text embeddings
   - `openai` for OpenAI embeddings
   - Custom embedding models based on your data

2. **Example with Sentence Transformers**:

```python
from sentence_transformers import SentenceTransformer

model = SentenceTransformer('all-MiniLM-L6-v2')

def create_vector_from_message(message, model):
    # Extract text from message
    text = message.get('message', '') + ' ' + json.dumps(message.get('data', {}))
    # Generate embedding
    vector = model.encode(text).tolist()
    return vector
```

## Configuration Options

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `KAFKA_BOOTSTRAP_SERVERS` | Kafka bootstrap servers | Required |
| `KAFKA_CERT_FOLDER` | Path to Kafka certificates | `./certs` |
| `KAFKA_TOPIC_NAME` | Kafka topic name | `diskless-topic` |
| `KAFKA_GROUP_ID` | Consumer group ID | `lancedb-consumer-group` |
| `KAFKA_RACK` | Rack ID for AZ awareness | Optional |
| `NUM_MESSAGES` | Number of messages to produce | `10` |
| `MESSAGE_DELAY` | Delay between messages (seconds) | `1.0` |
| `BATCH_SIZE` | Messages to batch before writing to LanceDB | `100` |
| `VECTOR_DIM` | Vector dimension | `128` |
| `LANCEDB_PATH` | Path to LanceDB database | `./lancedb_data` |
| `LANCEDB_TABLE_NAME` | LanceDB table name | `kafka_messages` |

## Best Practices

### Producer Best Practices

1. **Batching**: Use appropriate batch sizes for your workload
2. **Compression**: Enable compression (snappy, gzip, lz4) for better throughput
3. **Idempotence**: Always enable idempotence for exactly-once semantics
4. **AZ Awareness**: Set `KAFKA_RACK` for availability zone awareness

### Consumer Best Practices

1. **Batch Processing**: Process messages in batches for better performance
2. **Offset Management**: Monitor and manage consumer offsets
3. **Error Handling**: Implement robust error handling and retry logic
4. **Vector Indexing**: Create indexes on LanceDB tables for faster searches

### LanceDB Best Practices

1. **Index Creation**: Create vector indexes for efficient similarity search:

```python
table.create_index(
    metric="l2",  # or "cosine", "dot"
    num_partitions=256,
    num_sub_vectors=96,
    replace=True
)
```

2. **Schema Design**: Design your schema to include all necessary metadata
3. **Batch Writes**: Write data in batches for better performance

## Troubleshooting

### Connection Issues

- Verify `KAFKA_BOOTSTRAP_SERVERS` is correct
- Check that certificates are in the correct location
- Ensure certificates are not expired

### Consumer Lag

- Increase `BATCH_SIZE` for better throughput
- Adjust `fetch_min_bytes` and `fetch_max_wait_ms`
- Consider using multiple consumer instances

### LanceDB Issues

- Ensure `LANCEDB_PATH` directory is writable
- Check that vector dimensions are consistent
- Verify table schema matches your data

## Cleanup

To clean up resources:

```bash
# Remove LanceDB data
rm -rf ./lancedb_data

# Remove certificates (if needed)
rm -rf ./certs

# Terminate Kafka service (if created for testing)
avn service terminate --project $PROJECT_NAME --force $SERVICE_NAME
```

## Additional Resources

- [Aiven Kafka Documentation](https://docs.aiven.io/docs/products/kafka)
- [Kafka Diskless Topics](https://aiven.io/docs/products/kafka/diskless/concepts/diskless-topics-architecture)
- [LanceDB Documentation](https://lancedb.github.io/lancedb/)
- [Kafka Python Client](https://kafka-python.readthedocs.io/)

## License

This example code is provided as-is for demonstration purposes.
