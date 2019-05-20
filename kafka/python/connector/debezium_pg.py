import psutil
import psycopg2
import json
import argparse
import os
import time
import socket
import getpass
from kafka import KafkaConsumer
from aiven.client.client import AivenClient, Error

AIVEN_API_URL = "https://api.aiven.io"
CA_FILE = "cafile"
CERT_FILE = "certfile"
KEY_FILE = "keyfile"


def timeout(stop_after=200.0):
    """decorated function should return 0 when done and 1 when it should run again"""
    def wrap(func):
        def inner(self, *args, **kwargs):
            starttime = time.monotonic()
            timeout = stop_after + starttime
            while time.monotonic() < timeout:
                if not func(self, *args, **kwargs):
                    return
                time.sleep(3.0)
            print("This is taking too long. Request timed out.")
        return inner
    return wrap


class KafkaConnector:
    def __init__(self, config):
        self.config = config
        self.client = AivenClient(self.config["url"])
        self.pg = None
        self.kafka = None
        self.topic_name = None

    def login(self, token=None):
        if not token:
            token = self.client.authenticate_user(self.config["email"], self.config["password"])["token"]
        self.client.set_auth_token(token)

    @staticmethod
    def get_error_message(e):
        return json.loads(e)["message"]

    def create_services(self):
        print("Creating services")
        try:
            self.pg = self.client.get_service(self.config["project"], self.config["pg_name"])
            print(f"Service {self.config['pg_name']} already exists")
        except Error:
            print(f"Creating service {self.config['pg_name']}")
            self.pg = self.client.create_service(self.config["project"], self.config["pg_name"], "pg", "default", "hobbyist")

        kafka_config = {"kafka_connect": True}
        try:
            self.kafka = self.client.get_service(self.config["project"], self.config["kafka_name"])
            print(f"Service {self.config['kafka_name']} already exists")
            if not self.kafka["user_config"]["kafka_connect"]:
                print(f"Enabling Kafka Connect for {self.config['kafka_name']}")
                self.kafka = self.client.update_service(
                    self.config["project"], self.config["kafka_name"], user_config=kafka_config
                )
            else:
                print(f"Kafka Connect is already enabled on {self.config['kafka_name']}")
        except Error:
            print(f"Creating service {self.config['kafka_name']}")
            self.kafka = self.client.create_service(
                self.config["project"], self.config["kafka_name"], "kafka", "default", "business-4", user_config=kafka_config
            )

    @timeout(300)
    def wait_for_running(self):
        self.kafka = self.client.get_service(self.config["project"], self.config["kafka_name"])
        self.pg = self.client.get_service(self.config["project"], self.config["pg_name"])
        print(f"pg: {self.pg['state']} kafka: {self.kafka['state']}")
        if self.pg['state'] == "RUNNING" and self.kafka['state'] == "RUNNING":
            print("pg and Kafka services are running")
            return 0
        return 1

    def create_topic(self):
        if not self.topic_name:
            # expected topic name by the connector: servicename.schema.tablename
            self.topic_name = f"{self.pg['service_name']}.public.sensor_temperature"
        for topic in self.kafka["topics"]:
            if topic["topic_name"] == self.topic_name:
                print(f"Topic {self.topic_name} already exists")
                break
        else:
            print(f"Creating topic {self.topic_name}")
            self.client.create_service_topic(
                self.config["project"], self.config["kafka_name"], self.topic_name, 1, 2, 1, -1, 24, "delete"
            )

    def create_conector(self):
        connector_config = {}
        with open("debezium_pg.json") as config:
            connector_config = json.load(config)

        @timeout(300)
        def create(config):
            try:
                connectors = self.client.list_kafka_connectors(self.config["project"], self.config["kafka_name"])
                for connector in connectors["connectors"]:
                    if connector["name"] == connector_config["name"]:
                        print(f"Connector for {connector_config['name']} already exists")
                        return 0

                self.client.create_kafka_connector(self.config["project"], self.config["kafka_name"], config)
                print("Kafka PG connector created")
                return 0
            except Error as e:
                print("Kafka Connect not yet available: ", self.get_error_message(e))
            return 1

        connector_config["database.hostname"] = self.pg["service_uri_params"]["host"]
        connector_config["database.port"] = self.pg["service_uri_params"]["port"]
        connector_config["database.user"] = self.pg["service_uri_params"]["user"]
        connector_config["database.password"] = self.pg["service_uri_params"]["password"]
        connector_config["database.dbname"] = self.pg["service_uri_params"]["dbname"]
        connector_config["database.server.name"] = self.pg["service_name"]

        create(connector_config)

    @timeout(300)
    def create_table(self):
        try:
            conn = psycopg2.connect(self.pg["service_uri"])
        except psycopg2.OperationalError as e:
            print("{self.config['pg_name]} service not yet available. Waiting.", self.get_error_message(e))
            return 1

        with conn:
            with conn.cursor() as cursor:
                with open("sensor_temperature.sql", "r") as table_sql:
                    cursor.execute(table_sql.read())
        return 0

    def create_cert_files(self):
        print("Generating cert files")
        # these are used on the kafka consumer
        ca = self.client.get_project_ca(self.config["project"])
        with open(CA_FILE, "w") as cafile:
            cafile.write(ca["certificate"])
        with open(CERT_FILE, "w") as certfile:
            certfile.write(self.kafka["connection_info"]["kafka_access_cert"])
        with open(KEY_FILE, "w") as keyfile:
            keyfile.write(self.kafka["connection_info"]["kafka_access_key"])

    def store_sensor_data(self):
        print("Sending sensor data to PG")
        host = socket.gethostname()
        with psycopg2.connect(self.pg["service_uri"]) as conn:
            with conn.cursor() as cursor:
                for core in psutil.sensors_temperatures()["coretemp"]:
                    if core.label.startswith("C"):
                        print(f"device: {host} label: {core.label} temperature: {core.current}")
                        cursor.execute(
                            "INSERT INTO sensor_temperature (device, label, temperature) VALUES (%s, %s, %s);",
                            (host, core.label, core.current)
                        )

    def read_from_kafka(self):
        consumer = KafkaConsumer(
            self.topic_name,
            bootstrap_servers=self.kafka["connection_info"]["kafka"],
            group_id="sensor-temperature-demo",
            auto_offset_reset="earliest",
            security_protocol="SSL",
            ssl_cafile=CA_FILE,
            ssl_certfile=CERT_FILE,
            ssl_keyfile=KEY_FILE
        )
        print("Consuming Kafka Topic. Press Ctrl+C to exit")
        try:
            for msg in consumer:
                m = json.loads(msg.value.decode("utf-8"))
                print(f"offset: {msg.offset} payload: {m['after']}")
        except KeyboardInterrupt:
            consumer.commit()
            consumer.close()

    def run(self):
        self.login(self.config["token"])
        self.create_services()
        print("\nWaiting for serices to be running")
        self.wait_for_running()
        print()
        self.create_topic()
        print()
        self.create_conector()
        print("Creating PG sensor table if it does not exist")
        self.create_table()
        print()
        self.store_sensor_data()
        self.create_cert_files()
        print()
        self.read_from_kafka()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Use either TOKEN or EMAIL/PASSWORD for authenticating to Aiven API.",
        epilog="It is possible to define the arguments through environment variables: AIVEN_TOKEN, "
               "AIVEN_EMAIL, AIVEN_PASSWORD, AIVEN_PROJECT, AIVEN_URL, AIVEN_PG_NAME, AIVEN_KAFKA_NAME."
    )

    parser.add_argument(
        "--token", dest="token", metavar="AIVEN_TOKEN",
        default=os.environ.get("AIVEN_TOKEN"),
        help="Aiven api authentication token"
    )
    parser.add_argument(
        "--email", dest="email", metavar="AIVEN_EMAIL",
        default=os.environ.get("AIVEN_EMAIL"),
        help="Aiven console email"
    )
    parser.add_argument(
        "--password", dest="password", metavar="AIVEN_PASSWORD",
        default=os.environ.get("AIVEN_PASSWORD"),
        help="Aiven console password"
    )
    parser.add_argument(
        "--project", dest="project", metavar="AIVEN_PROJECT",
        default=os.environ.get("AIVEN_PROJECT"),
        help="project to create services in"
    )
    parser.add_argument(
        "--url", dest="url", metavar="AIVEN_API_URL",
        default=os.environ.get("AIVEN_API_URL") or AIVEN_API_URL,
        help=f"Aiven cloud url (default: {AIVEN_API_URL})"
    )
    parser.add_argument(
        "--pg-name", dest="pg_name", metavar="AIVEN_PG_NAME",
        default=os.environ.get("AIVEN_PG_NAME") or "pgconnector",
        help="Aiven Postgres service name"
    )
    parser.add_argument(
        "--kafka-name", dest="kafka_name", metavar="AIVEN_KAFKA_NAME",
        default=os.environ.get("AIVEN_KAFKA_NAME") or "kafkaconnector",
        help="Aiven Kafka service name"
    )

    config = parser.parse_args()

    if not (config.token or config.email and config.password):
        if not config.email:
            config.email = input("Username (email): ")
        if not config.password:
            config.password = getpass.getpass("Password: ")
        print()

    if not config.project:
        config.project = input("Project name: ")
        print()

    kafka_connector = KafkaConnector(vars(config))
    kafka_connector.run()
