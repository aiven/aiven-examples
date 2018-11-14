import glob
import json
import subprocess
import time

import pytest
import os
import contextlib
from os.path import join

from aiven.client.client import Error

from tests import AivenExampleTest, ServiceSpec


@contextlib.contextmanager
def chdir(path):
    prev_cwd = os.getcwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(prev_cwd)


class PostgresTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="pg", version='latest', plan='hobbyist'),
    )

    def test_python_example(self):
        command = f"python postgresql/python/main.py --service-uri {self.service_uri()}"
        self.verify_postgres_example(command)

    def test_go_example(self):
        command = f"go run postgresql/go/main.go --service-uri {self.service_uri()}"
        self.verify_postgres_example(command)

    def verify_postgres_example(self, command):
        result = self.execute(command)
        assert result.returncode == 0
        assert result.stdout == "Successfully connected to: defaultdb\n"

    def service_uri(self):
        return self.services['pg']['pg-latest-hobbyist']["connection_info"]["pg"][0]


class CassandraTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="cassandra", version='latest', plan='startup-4'),
    )

    def test_python_example(self):
        command = './cassandra/python/main.py --host {host} --port {port} --password {password} --ca-path {ca_path}'
        result = self.execute(command.format(**self.test_params), check=True)
        assert "Hello from Python!" in result.stdout

    def test_go_example(self):
        go_files = " ".join(glob.glob('cassandra/go/*.go'))
        command = f"go run {go_files}" + " --host {host} --port {port} --password {password} --ca-path {ca_path}"
        result = self.execute(command.format(**self.test_params), check=True)
        assert "Hello from golang!" in result.stdout

    def test_java_example(self):
        with chdir('cassandra/java'):
            command = "./gradlew -q run --args='" \
                      "--host {host} --port {port} --password {password} --ca-path {ca_path}'"
            result = self.execute(command.format(**self.test_params), check=True)
            assert "Hello from Java!" in result.stdout

    @pytest.fixture(autouse=True)
    def setup(self, tmpdir):
        params = self.services['cassandra']['cassandra-latest-startup-4']['service_uri_params']
        host, port, password = params['host'], params['port'], params['password']
        self.ca_path = join(tmpdir.strpath, 'ca.pem')
        with open(self.ca_path, 'w+') as f:
            f.write(self.project_ca)
        self.test_params = dict(host=host, port=port, password=password, ca_path=self.ca_path)

    def tearDown(self):
        os.remove(self.ca_path)


class ElasticsearchTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="elasticsearch", version='latest', plan='hobbyist'),
    )

    def test_python_example(self):
        service_uri = self.services["elasticsearch"]["elasticsearch-latest-hobbyist"]["service_uri"]
        result = self.execute(f"./elasticsearch/python/main.py --url {service_uri}", check=True)
        result_json = json.loads(result.stdout)
        assert result_json['_source']['name'] == 'John'
        assert result_json['_source']['birth_year'] == 1980

    def test_go_example(self):
        params = self.services["elasticsearch"]["elasticsearch-latest-hobbyist"]["service_uri_params"]
        host, port, password = params["host"], params["port"], params["password"]
        go_files = " ".join(glob.glob('elasticsearch/go/*.go'))
        result = self.execute(f"go run {go_files} --url https://{host}:{port} --password {password}", check=True)
        result_json = json.loads(result.stdout)
        assert result_json['name'] == 'John'
        assert result_json['birth_year'] == 1980


class InfluxDBTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="influxdb", version='latest', plan='hobbyist'),
    )

    def test_python_example(self):
        service_uri = self.services['influxdb']['influxdb-latest-hobbyist']['service_uri']
        result = self.execute(f"./influxdb/python/main.py --url {service_uri}", check=True)
        result_json = json.loads(result.stdout)
        assert "time" in result_json
        assert "value" in result_json
        assert result_json["value"] == 0.95

    def test_go_example(self):
        params = self.services['influxdb']['influxdb-latest-hobbyist']["service_uri_params"]
        host, port, password = params["host"], params["port"], params["password"]
        go_files = " ".join(glob.glob('influxdb/go/*.go'))
        result = self.execute(f"go run {go_files} --host https://{host}:{port} --password {password}", check=True)
        assert "cpu_load_short map" in result.stdout
        assert "[time value]" in result.stdout


class KafkaTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="kafka", version='latest', plan='startup-2'),
    )

    def test_python_example(self):
        command = "./kafka/python/main.py " \
                  "--service-uri {service_uri} " \
                  "--ca-path {ca_path} " \
                  "--key-path {access_key_path} " \
                  "--cert-path {access_cert_path} " \
            .format(**self.test_params)
        result = self.execute(f"{command} --producer", check=True)
        assert "Sending: message number 1" in result.stdout

        for sleep_duration in (1, 3, 6, 15, 30):
            result = self.execute(f"{command} --consumer")
            if "message number 1" in result.stdout:
                return
            time.sleep(sleep_duration)
        assert False, "Failed to consume message from Kafka"

    def test_go_example(self):
        go_files = " ".join(glob.glob('kafka/go/*.go'))
        command = f"go run {go_files} " \
                  "-service-uri {service_uri} " \
                  "-ca-path {ca_path} " \
                  "-key-path {access_key_path} " \
                  "-cert-path {access_cert_path} " \
            .format(**self.test_params)

        result = self.execute(f"{command} --producer", check=True)
        assert "Testing 1" in result.stdout

        p = subprocess.Popen(f"{command} -consumer".split(), stdout=subprocess.PIPE, bufsize=0)
        assert "Testing 1" in p.stdout.readline().decode('utf-8')

    @pytest.fixture(autouse=True)
    def setup(self, tmpdir):
        for topic in ("python_example_topic", "go_example_topic"):
            try:
                self.client.create_service_topic(self.project,
                                                 service='kafka-latest-startup-2',
                                                 topic=topic,
                                                 partitions=1, replication=3,
                                                 min_insync_replicas=1, retention_bytes=-1, retention_hours=-1,
                                                 cleanup_policy='delete')
            except Error as e:
                if e.status != 409:
                    raise

        service = self.services['kafka']['kafka-latest-startup-2']
        host, port = service['service_uri_params']['host'], service['service_uri_params']['port']
        service_uri = f"{host}:{port}"
        self.ca_path = join(tmpdir.strpath, 'ca.pem')
        with open(self.ca_path, 'w+') as f:
            f.write(self.project_ca)

        self.access_key_path = join(tmpdir.strpath, "service.key")
        with open(self.access_key_path, "w+") as f:
            f.write(service["connection_info"]["kafka_access_key"])

        self.access_cert_path = join(tmpdir.strpath, "service.cert")
        with open(self.access_cert_path, "w+") as f:
            f.write(service["connection_info"]["kafka_access_cert"])

        self.test_params = dict(service_uri=service_uri,
                                ca_path=self.ca_path,
                                access_key_path=self.access_key_path,
                                access_cert_path=self.access_cert_path)

    def tearDown(self):
        os.remove(self.ca_path)
        os.remove(self.access_key_path)
        os.remove(self.access_cert_path)


class RedisTest(AivenExampleTest):
    required_services = (
        ServiceSpec(type="redis", version='latest', plan='hobbyist'),
    )

    def test_python_example(self):
        params = self.services['redis']['redis-latest-hobbyist']['service_uri_params']
        host, port, password = params['host'], params['port'], params['password']
        expected = "The value for 'pythonRedisExample' is: 'python'\n"
        self.verify_redis_example(f"./redis/python/main.py --host {host} --port {port} --password {password}",
                                  expected=expected)

    def test_go_example(self):
        params = self.services['redis']['redis-latest-hobbyist']['service_uri_params']
        host, port, password = params['host'], params['port'], params['password']
        go_files = " ".join(glob.glob('redis/go/*.go'))
        expected = "The value for 'goRedisExample' is: 'golang'\n"
        self.verify_redis_example(f"go run {go_files} --host {host} --port {port} --password {password}",
                                  expected=expected)

    def verify_redis_example(self, command, expected):
        result = self.execute(command)
        assert result.stdout == expected
