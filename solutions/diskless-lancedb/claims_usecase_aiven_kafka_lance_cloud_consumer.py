import json
import lancedb
import pandas as pd
from confluent_kafka import Consumer, KafkaError

# --- Configuration ---
AIVEN_CONF = {
    'bootstrap.servers': 'Aiven Kafka Bootstrap Servers',
    'security.protocol': 'SSL',
    'ssl.ca.location': '/path/to/ca.pem',
    'ssl.certificate.location': '/path/to/service.cert',
    'ssl.key.location': '/path/to/service.key',
    'group.id': 'lancedb-ingestor-1',
    'auto.offset.reset': 'earliest'
}

LANCEDB_URI = "db://URI" # Found in LanceDB Cloud Console
LANCEDB_API_KEY = "sk_...."
TABLE_NAME = "insurance_claims"

# --- Initialize LanceDB ---
db = lancedb.connect(LANCEDB_URI, api_key=LANCEDB_API_KEY)

def ingest_to_lancedb(data):
    """
    Ingests a list of claim records into LanceDB.
    Note: LanceDB handles schema inference from the first batch.
    """
    if not data:
        return
    # Open or create the table
    if TABLE_NAME in db.table_names():
        table = db.open_table(TABLE_NAME)
        table.add(data)
    else:
        db.create_table(TABLE_NAME, data=data)
    print(f"Successfully ingested {len(data)} records to LanceDB.")

# --- Kafka Consumer Loop ---
consumer = Consumer(AIVEN_CONF)
consumer.subscribe(['insurance-claims'])

print(f"Consuming from Aiven and ingesting to {LANCEDB_URI}...")


batch = []
batch_size = 10  # Ingest in small batches for efficiency

try:
    while True:
        msg = consumer.poll(1.0)

        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                continue
            else:
                print(msg.error())
                break

        # Parse claim data
        claim = json.loads(msg.value().decode('utf-8'))
        batch.append(claim)
 # Process batch
        if len(batch) >= batch_size:
            ingest_to_lancedb(batch)
            batch = []

except KeyboardInterrupt:
    pass
finally:
    if batch:
        ingest_to_lancedb(batch)
