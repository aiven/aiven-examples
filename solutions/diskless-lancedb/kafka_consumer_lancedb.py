"""
Kafka Consumer for Aiven Kafka Diskless Topics with LanceDB Integration

This script consumes messages from Aiven Kafka Diskless topics and writes
them to LanceDB for vector storage and search.
"""

import os
import json
import logging
from datetime import datetime
from kafka import KafkaConsumer
from kafka.errors import KafkaError
import lancedb
import pandas as pd
from typing import Dict, List, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def create_consumer(topic_name: str, group_id: str = None):
    """
    Create and configure Kafka consumer optimized for diskless topics.
    
    Args:
        topic_name: Name of the Kafka topic to consume from
        group_id: Consumer group ID (optional)
    
    Returns:
        KafkaConsumer: Configured consumer instance
    """
    bootstrap_servers = os.environ.get("KAFKA_BOOTSTRAP_SERVERS")
    cert_folder = os.environ.get("KAFKA_CERT_FOLDER", "./certs")
    
    if not bootstrap_servers:
        raise ValueError("KAFKA_BOOTSTRAP_SERVERS environment variable is required")
    
    if not group_id:
        group_id = os.environ.get("KAFKA_GROUP_ID", "lancedb-consumer-group")
    
    # Diskless-optimized consumer settings
    consumer_config = {
        'bootstrap_servers': bootstrap_servers,
        'security_protocol': 'SSL',
        'ssl_cafile': os.path.join(cert_folder, 'ca.pem'),
        'ssl_certfile': os.path.join(cert_folder, 'service.cert'),
        'ssl_keyfile': os.path.join(cert_folder, 'service.key'),
        'value_deserializer': lambda m: json.loads(m.decode('utf-8')),
        'key_deserializer': lambda k: k.decode('utf-8') if k else None,
        'auto_offset_reset': 'earliest',  # Start from beginning if no offset
        'enable_auto_commit': True,
        'group_id': group_id,
        # Diskless-optimized settings
        'fetch_max_bytes': 1048576,  # 1MiB
        'max_partition_fetch_bytes': 1048576,  # 1MiB
        'fetch_min_bytes': 1,  # Optional: for higher throughput
        'fetch_max_wait_ms': 500,  # Optional: for higher throughput
    }
    
    # Add client.id with AZ awareness if rack is provided
    rack = os.environ.get("KAFKA_RACK")
    if rack:
        client_id = f"diskless-consumer,diskless_az={rack}"
        consumer_config['client_id'] = client_id
    
    try:
        consumer = KafkaConsumer(topic_name, **consumer_config)
        logger.info(f"Kafka consumer created successfully for topic '{topic_name}'")
        return consumer
    except Exception as e:
        logger.error(f"Failed to create Kafka consumer: {e}")
        raise


def create_vector_from_message(message: Dict[str, Any], vector_dim: int = 128) -> List[float]:
    """
    Create a vector representation from a Kafka message.
    
    This is a simple example that creates a vector from message data.
    In production, you would use proper embeddings (e.g., sentence transformers).
    
    Args:
        message: Kafka message dictionary
        vector_dim: Dimension of the vector to create
    
    Returns:
        List of floats representing the vector
    """
    # Simple hash-based vector generation (replace with proper embeddings)
    import hashlib
    
    # Create a hash from message content
    message_str = json.dumps(message, sort_keys=True)
    hash_obj = hashlib.sha256(message_str.encode())
    hash_bytes = hash_obj.digest()
    
    # Convert hash to vector of specified dimension
    vector = []
    for i in range(vector_dim):
        # Use hash bytes cyclically to fill vector
        byte_val = hash_bytes[i % len(hash_bytes)]
        # Normalize to [-1, 1] range
        normalized = (byte_val / 255.0) * 2 - 1
        vector.append(normalized)
    
    return vector


def prepare_lancedb_data(messages: List[Dict[str, Any]], vector_dim: int = 128) -> pd.DataFrame:
    """
    Prepare messages for insertion into LanceDB.
    
    Args:
        messages: List of Kafka messages
        vector_dim: Dimension of vectors to create
    
    Returns:
        pandas DataFrame ready for LanceDB
    """
    records = []
    
    for msg in messages:
        # Extract message data
        msg_data = msg.get('value', {})
        
        # Create vector representation
        vector = create_vector_from_message(msg_data, vector_dim)
        
        # Prepare record for LanceDB
        record = {
            'id': msg_data.get('id', hash(json.dumps(msg_data))),
            'vector': vector,
            'timestamp': msg_data.get('timestamp', datetime.now().isoformat()),
            'message': msg_data.get('message', ''),
            'kafka_offset': msg.get('offset', -1),
            'kafka_partition': msg.get('partition', -1),
            'kafka_key': msg.get('key', ''),
            'raw_data': json.dumps(msg_data),  # Store original message as JSON string
        }
        
        # Add any additional fields from message data
        if 'data' in msg_data:
            record['category'] = msg_data['data'].get('category', '')
            record['value'] = msg_data['data'].get('value', 0)
        
        records.append(record)
    
    return pd.DataFrame(records)


def setup_lancedb_table(db_path: str, table_name: str, vector_dim: int = 128):
    """
    Setup or get LanceDB table.
    
    Args:
        db_path: Path to LanceDB database
        table_name: Name of the table
        vector_dim: Dimension of vectors
    
    Returns:
        LanceDB table instance
    """
    import pyarrow as pa
    import lancedb
    
    # Connect to LanceDB
    db = lancedb.connect(db_path)
    logger.info(f"Connected to LanceDB at '{db_path}'")
    
    # Check if table exists
    try:
        table = db.open_table(table_name)
        logger.info(f"Opened existing table '{table_name}'")
        return table
    except Exception:
        # Table doesn't exist, create it
        logger.info(f"Creating new table '{table_name}'")
        
        # Define schema
        schema = pa.schema([
            pa.field('id', pa.int64()),
            pa.field('vector', lancedb.vector(vector_dim)),
            pa.field('timestamp', pa.string()),
            pa.field('message', pa.string()),
            pa.field('kafka_offset', pa.int64()),
            pa.field('kafka_partition', pa.int32()),
            pa.field('kafka_key', pa.string()),
            pa.field('raw_data', pa.string()),
            pa.field('category', pa.string()),
            pa.field('value', pa.int64()),
        ])
        
        # Create empty table with schema
        table = db.create_table(table_name, schema=schema)
        logger.info(f"Created table '{table_name}' with vector dimension {vector_dim}")
        
        return table


def consume_and_store(
    consumer: KafkaConsumer,
    db_path: str,
    table_name: str,
    batch_size: int = 100,
    vector_dim: int = 128
):
    """
    Consume messages from Kafka and store them in LanceDB.
    
    Args:
        consumer: KafkaConsumer instance
        db_path: Path to LanceDB database
        table_name: Name of the LanceDB table
        batch_size: Number of messages to batch before writing to LanceDB
        vector_dim: Dimension of vectors
    """
    # Setup LanceDB table
    table = setup_lancedb_table(db_path, table_name, vector_dim)
    
    message_batch = []
    total_messages = 0
    
    logger.info(f"Starting to consume messages (batch size: {batch_size})")
    
    try:
        for message in consumer:
            # Extract message information
            msg_data = {
                'value': message.value,
                'key': message.key,
                'offset': message.offset,
                'partition': message.partition,
                'timestamp': message.timestamp,
            }
            
            message_batch.append(msg_data)
            total_messages += 1
            
            logger.debug(
                f"Received message: offset={message.offset}, "
                f"partition={message.partition}, key={message.key}"
            )
            
            # When batch is full, write to LanceDB
            if len(message_batch) >= batch_size:
                try:
                    df = prepare_lancedb_data(message_batch, vector_dim)
                    table.add(df)
                    logger.info(
                        f"Wrote batch of {len(message_batch)} messages to LanceDB "
                        f"(total: {total_messages})"
                    )
                    message_batch = []
                except Exception as e:
                    logger.error(f"Failed to write batch to LanceDB: {e}")
                    # Continue processing despite error
        
    except KeyboardInterrupt:
        logger.info("Consumer interrupted by user")
    except Exception as e:
        logger.error(f"Consumer error: {e}")
        raise
    finally:
        # Write any remaining messages
        if message_batch:
            try:
                df = prepare_lancedb_data(message_batch, vector_dim)
                table.add(df)
                logger.info(
                    f"Wrote final batch of {len(message_batch)} messages to LanceDB"
                )
            except Exception as e:
                logger.error(f"Failed to write final batch to LanceDB: {e}")
        
        consumer.close()
        logger.info(f"Consumer closed. Total messages processed: {total_messages}")


def main():
    """Main function to run the consumer."""
    topic_name = os.environ.get("KAFKA_TOPIC_NAME", "diskless-topic")
    group_id = os.environ.get("KAFKA_GROUP_ID", "lancedb-consumer-group")
    db_path = os.environ.get("LANCEDB_PATH", "./lancedb_data")
    table_name = os.environ.get("LANCEDB_TABLE_NAME", "kafka_messages")
    batch_size = int(os.environ.get("BATCH_SIZE", "100"))
    vector_dim = int(os.environ.get("VECTOR_DIM", "128"))
    
    try:
        consumer = create_consumer(topic_name, group_id)
        consume_and_store(consumer, db_path, table_name, batch_size, vector_dim)
    except Exception as e:
        logger.error(f"Consumer failed: {e}")
        raise


if __name__ == "__main__":
    main()
