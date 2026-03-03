"""
Kafka Producer for Aiven Kafka Diskless Topics

This script produces messages to Aiven Kafka Diskless topics with optimized
settings for diskless storage.
"""

import os
import json
import time
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import KafkaError
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def create_producer():
    """
    Create and configure Kafka producer optimized for diskless topics.
    
    Returns:
        KafkaProducer: Configured producer instance
    """
    bootstrap_servers = os.environ.get("KAFKA_BOOTSTRAP_SERVERS")
    cert_folder = os.environ.get("KAFKA_CERT_FOLDER", "./certs")
    
    if not bootstrap_servers:
        raise ValueError("KAFKA_BOOTSTRAP_SERVERS environment variable is required")
    
    # Diskless-optimized producer settings
    producer_config = {
        'bootstrap_servers': bootstrap_servers,
        'security_protocol': 'SSL',
        'ssl_cafile': os.path.join(cert_folder, 'ca.pem'),
        'ssl_certfile': os.path.join(cert_folder, 'service.cert'),
        'ssl_keyfile': os.path.join(cert_folder, 'service.key'),
        'value_serializer': lambda v: json.dumps(v).encode('utf-8'),
        'key_serializer': lambda k: k.encode('utf-8') if k else None,
        # Diskless-optimized settings
        'linger_ms': 100,  # Wait up to 100ms to batch messages
        'batch_size': 16384,  # 16KiB batch size
        'max_request_size': 1048576,  # 1MiB max request size
        'acks': 'all',  # Wait for all replicas
        'enable_idempotence': True,  # Ensure exactly-once semantics
        'max_in_flight_requests_per_connection': 2,  # Reduce from default 5
        'compression_type': 'snappy',  # Optional: compress messages
    }
    
    # Add client.id with AZ awareness if rack is provided
    rack = os.environ.get("KAFKA_RACK")
    if rack:
        client_id = f"diskless-producer,diskless_az={rack}"
        producer_config['client_id'] = client_id
    
    try:
        producer = KafkaProducer(**producer_config)
        logger.info("Kafka producer created successfully")
        return producer
    except Exception as e:
        logger.error(f"Failed to create Kafka producer: {e}")
        raise


def produce_sample_messages(producer, topic_name, num_messages=10, delay=1):
    """
    Produce sample messages to the specified topic.
    
    Args:
        producer: KafkaProducer instance
        topic_name: Name of the Kafka topic
        num_messages: Number of messages to produce
        delay: Delay between messages in seconds
    """
    logger.info(f"Producing {num_messages} messages to topic '{topic_name}'")
    
    for i in range(num_messages):
        message = {
            "id": i + 1,
            "timestamp": datetime.now().isoformat(),
            "message": f"Sample message {i + 1}",
            "data": {
                "value": i * 10,
                "category": f"category_{i % 3}",
                "metadata": {
                    "source": "kafka-producer",
                    "version": "1.0"
                }
            }
        }
        
        try:
            # Send message (key is optional)
            future = producer.send(
                topic_name,
                value=message,
                key=f"key_{i}"
            )
            
            # Wait for the message to be sent (optional, for confirmation)
            record_metadata = future.get(timeout=10)
            logger.info(
                f"Message {i + 1} sent to topic={record_metadata.topic}, "
                f"partition={record_metadata.partition}, "
                f"offset={record_metadata.offset}"
            )
            
            time.sleep(delay)
            
        except KafkaError as e:
            logger.error(f"Failed to send message {i + 1}: {e}")
    
    # Ensure all messages are sent
    producer.flush()
    logger.info("All messages sent successfully")


def main():
    """Main function to run the producer."""
    topic_name = os.environ.get("KAFKA_TOPIC_NAME", "diskless-topic")
    num_messages = int(os.environ.get("NUM_MESSAGES", "10"))
    delay = float(os.environ.get("MESSAGE_DELAY", "1.0"))
    
    try:
        producer = create_producer()
        produce_sample_messages(producer, topic_name, num_messages, delay)
    except Exception as e:
        logger.error(f"Producer failed: {e}")
        raise
    finally:
        if 'producer' in locals():
            producer.close()
            logger.info("Producer closed")


if __name__ == "__main__":
    main()
