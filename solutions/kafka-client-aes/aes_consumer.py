from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import padding
from kafka import KafkaConsumer
import base64, os


# 128-bit encryption key
# This must be stored securely elsewhere
key = b"\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c"

# Kafka server
BOOTSTRAP_SERVER = os.environ.get("BOOTSTRAP_SERVER")


def decrypt(ciphertext):
    # Decrypt data using AES-128 in CBC mode
    ciphertext = base64.b64decode(ciphertext)
    cipher = Cipher(algorithms.AES(key), modes.CBC(key), backend=default_backend())
    decryptor = cipher.decryptor()
    plaintext = decryptor.update(ciphertext) + decryptor.finalize()
    return unpad(plaintext)


def unpad(data):
    # Unpad data that was encrypted
    unpadder = padding.PKCS7(128).unpadder()
    return unpadder.update(data) + unpadder.finalize()


class EncryptedValueDeserializer:
    def __call__(self, value):
        return decrypt(value)


consumer = KafkaConsumer(
    bootstrap_servers=BOOTSTRAP_SERVER,
    value_deserializer=EncryptedValueDeserializer(),
    security_protocol="SSL",
    ssl_cafile="ca.pem",
    ssl_certfile="service.cert",
    ssl_keyfile="service.key",
    group_id="group_id_1",
    auto_offset_reset="earliest",
)

consumer.subscribe(["my-secrets"])

for message in consumer:
    print(message.value)
