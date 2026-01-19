import json
import time
import random
from faker import Faker
from confluent_kafka import Producer

# Configuration for Aiven Kafka
conf = {
    'bootstrap.servers': 'Aiven Kafka Bootstrap Servers',
    'security.protocol': 'SSL',
    'ssl.ca.location': '/path/to/ca.pem',
    'ssl.certificate.location': '/path/to/service.cert',
    'ssl.key.location': '/path/to/service.key',
}

producer = Producer(conf)
fake = Faker()

def generate_claim():
    # Randomly decide if this is a high-value/suspicious claim
    is_suspicious = random.random() < 0.15

    claim_amount = random.uniform(500, 3000) if not is_suspicious else random.uniform(10000, 50000)

    claim = {
        "id": fake.uuid4(),
        "policy_id": f"POL-{fake.random_int(1000, 9999)}",
        "description": fake.sentence(nb_words=12) if not is_suspicious else "Total loss, multiple vehicles involved, severe structural damage.",
        "amount": round(claim_amount, 2),
        "policy_limit": 25000,
        "incident_date": fake.date_this_year().isoformat(),
        "policy_holder": fake.name(),
        "claim_type": fake.random_element(elements=("Auto", "Home", "Life", "Health"))
    }
    return claim

def delivery_report(err, msg):
    if err is not None:
        print(f"Message delivery failed: {err}")
    else:
        print(f"Claim {msg.key().decode('utf-8')} sent to {msg.topic()}")

print("Starting synthetic claim stream...")
try:
    while True:
        data = generate_claim()
        producer.produce(
            'insurance-claims',
            key=data['id'],
            value=json.dumps(data).encode('utf-8'),
            callback=delivery_report
        )
        producer.poll(0)
        time.sleep(random.uniform(1, 5)) # Simulate real-world arrival
except KeyboardInterrupt:
    producer.flush()