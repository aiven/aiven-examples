from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
from kafka import KafkaProducer
import base64, os
import json
from datetime import datetime

# 128-bit encryption key
# This must be stored securely elsewhere
key = b"\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c"

# Kafka server
BOOTSTRAP_SERVER = os.environ.get("BOOTSTRAP_SERVER")


def encrypt(plaintext):
    # Encrypt data using AES-128 in CBC mode
    cipher = Cipher(algorithms.AES(key), modes.CBC(key), backend=default_backend())
    encryptor = cipher.encryptor()
    padded_plaintext = pad(plaintext)
    ciphertext = encryptor.update(padded_plaintext) + encryptor.finalize()
    return base64.b64encode(ciphertext)


def pad(data):
    # Pad data to be encrypted
    padder = padding.PKCS7(128).padder()
    padded_data = padder.update(data) + padder.finalize()
    return padded_data


class EncryptedValueSerializer:
    def __call__(self, msg):
        return encrypt(bytes(msg, "utf-8"))


producer = KafkaProducer(
    bootstrap_servers=BOOTSTRAP_SERVER,
    security_protocol="SSL",
    ssl_cafile="ca.pem",
    ssl_certfile="service.cert",
    ssl_keyfile="service.key",
    value_serializer=EncryptedValueSerializer(),
)

for i in range(10):
    producer.send(
        "my-secrets", json.dumps({"msg": "this is a test", "time": str(datetime.now())})
    )

producer.flush()
