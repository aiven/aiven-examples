from paho.mqtt import client as mqtt_client
from confluent_kafka import SerializingProducer
from confluent_kafka.serialization import StringSerializer
import json
import os
import time
from prometheus_kafka_producer.metrics_manager import ProducerMetricsManager
from prometheus_client import start_http_server

metric_manager = ProducerMetricsManager()

broker = 'tie.digitraffic.fi'
port = 61619
topic = "weather/#"

client_id = "tms-demo-ingest"

def connect_kafka() -> SerializingProducer:
    producer_config = {
        'bootstrap.servers': os.getenv("BOOTSTRAP_SERVERS"),
        "statistics.interval.ms": 10000,
        'client.id': client_id,
        'key.serializer': StringSerializer("utf8"),
        'value.serializer': StringSerializer("utf8"),
        'compression.type': 'gzip',
        'security.protocol': 'SSL',
        'ssl.ca.location': '/etc/streams/tms-ingest-cert/ca.pem',
        'ssl.certificate.location': '/etc/streams/tms-ingest-cert/service.cert',
        'ssl.key.location': '/etc/streams/tms-ingest-cert/service.key', 
        'stats_cb': metric_manager.send,      
    }
    producer = SerializingProducer(producer_config)
    return producer

producer = connect_kafka()

def connect_mqtt() -> mqtt_client:
    print("Connecting client {}".format(client_id))
    def on_connect(client, userdata, flags, rc):
        if rc == 0:
            print("Connected, return code {}\n".format(rc))
            subscribe(client)
        else:
            print("Failed to connect, return code {}\n".format(rc))

    def on_disconnect(client, userdata, rc):
        print("Disconnected, return code {}\n".format(rc))

    client = mqtt_client.Client(client_id = client_id, transport="websockets")
    client.on_disconnect = on_disconnect
    client.on_connect = on_connect
    client.username_pw_set(username=os.getenv("MQTT_USER"), password=os.getenv("MQTT_PASSWORD"))
    client.tls_set()
    client.connect(broker, port)
    return client

def subscribe(client: mqtt_client):
    def on_message(client, userdata, msg):
        try:
            json_message = json.loads(msg.payload.decode())
            roadstation_id = json_message.get("roadStationId")
            if roadstation_id:
                producer.produce(topic="observations.weather.raw", key=str(json_message["roadStationId"]), 
                value=json.dumps(json_message))
            else:
                print("roadStationId not found: {}".format(msg.payload.decode()))
        except ValueError:
            print("Failed to decode message as JSON: {}".format(msg.payload.decode()))
  
    client.subscribe(topic)
    client.on_message = on_message


def run():
    client = connect_mqtt()            
    client.loop_forever()
    producer.flush()


if __name__ == '__main__':
    start_http_server(9091)
    run()
