from confluent_kafka import avro
from confluent_kafka import Consumer
from confluent_kafka.avro import AvroConsumer, CachedSchemaRegistryClient
from confluent_kafka.avro.serializer.message_serializer import MessageSerializer as AvroSerde
from prometheus_kafka_consumer.metrics_manager import ConsumerMetricsManager
from prometheus_client import start_http_server

import requests
import unicodedata
import os

metric_manager = ConsumerMetricsManager()
influxdb_client = os.getenv("M3_INFLUXDB_URL").rstrip()
influxdb_cred = os.getenv("M3_INFLUXDB_CREDENTIALS").rstrip()
group_name = "tms-demo-m3-sink"

consumer_config = {"bootstrap.servers": os.getenv("BOOTSTRAP_SERVERS"),
                        "statistics.interval.ms": 10000,
                        "group.id": group_name,
                        "client.id": group_name,
                        "stats_cb": metric_manager.send,
                        "max.poll.interval.ms": 30000,
                        "session.timeout.ms": 20000,
                        "default.topic.config": {"auto.offset.reset": "latest"},
                        "security.protocol": "SSL",
                        "ssl.ca.location": "/etc/streams/tms-sink-cert/ca.pem",
                        "ssl.certificate.location": "/etc/streams/tms-sink-cert/service.cert",
                        "ssl.key.location": "/etc/streams/tms-sink-cert/service.key"
                       }

schema_registry_config = {"url": os.getenv("SCHEMA_REGISTRY")}
schema_registry = CachedSchemaRegistryClient(schema_registry_config)
avro_serde = AvroSerde(schema_registry)
deserialize_avro = avro_serde.decode_message

def get_name_or_default(name):
    if not name:
        return str("-")
    else:        
        name = unicodedata.normalize('NFD', name)
        name = name.encode('ascii', 'ignore').decode('ascii')
        name = name.replace(" ", "_")
    return name

def to_buffer(buffer: list, message):
    try:                    
        deserialized_message = deserialize_avro(message=message.value(), is_key=False)        
    except Exception as e:                    
        print(f"Failed deserialize avro payload: {message.value()}\n{e}")
    else:
        values = []
        sensor_name_str = ''
        values_str = ''
        measurement_name = ''
        if message.topic() == 'observations.weather.multivariate':
            sensor_name_str = 'all'
            measurement_name = 'observations_mv'
            for key, value in deserialized_message['measurements'].items():
                values.append(key + '=' + str(value))
            values_str = ','.join(values)
        else:
            measurement_name = 'observations'
            sensor_name_str = get_name_or_default(deserialized_message["name"])
            values_str = f'sensorValue={deserialized_message["sensorValue"]}'

        buffer.append("{measurement},service=m3-sink,roadStationId={road_station_id},municipality={municipality},province={province},geohash={geohash},name={sensor_name} {sensor_values} {timestamp}"                    
            .format(measurement=measurement_name,
                    road_station_id=deserialized_message["roadStationId"],                    
                    municipality=get_name_or_default(deserialized_message["municipality"]),
                    province=get_name_or_default(deserialized_message["province"]),
                    geohash=deserialized_message["geohash"],
                    sensor_name=sensor_name_str,
                    sensor_values=values_str,
                    timestamp=deserialized_message["measuredTime"] * 1000 * 1000))

def flush_buffer(buffer: list):
    print(f"Flushing {len(buffer)} records to M3")
    payload = str("\n".join(buffer))    
    response = requests.post(influxdb_client, data=payload, 
    auth=(influxdb_cred.split(":")[0],influxdb_cred.split(":")[1]), 
    headers={'Content-Type': 'application/x-www-form-urlencoded'})
    if response.status_code == 400:
        print(f"{response.text} Skipping too old records")
        buffer.clear()
        return True
    if response.status_code != 204:        
        print(f"Failed to store to M3 {response.status_code}\n{response.text}")
        return False
    
    buffer.clear()
    return True

def consume_record(lines: list):    
    consumer = Consumer(consumer_config)    
    consumer.subscribe(["observations.weather.multivariate", "observations.weather.municipality"])

    while True:
        try:
            message = consumer.poll(1)
        except Exception as e:
            print(f"Exception while trying to poll messages - {e}")
            exit(-1)
        else:
            if message:
                to_buffer(lines, message)
                                   
                if (len(lines) > 1000 and flush_buffer(lines) == True):
                    consumer.commit()

if __name__ == "__main__":
    start_http_server(9091)
    lines = []
    consume_record(lines)
    
