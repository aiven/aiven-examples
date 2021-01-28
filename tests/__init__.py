import json
import logging
import os
import shlex
import subprocess
import time
import unittest

import pytest

from collections import defaultdict
from multiprocessing.pool import ThreadPool
from aiven.client import AivenClient
from aiven.client.client import Error

log = logging.getLogger(__name__)


class ServiceSpec:
    def __init__(self, type, version, plan):
        self.type = type
        self.version = version
        self.plan = plan

    @property
    def name(self):
        return f"{self.type}-{self.version}-{self.plan}"

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        return hash(self) == hash(other)


class ServiceManager:
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.client = AivenClient(base_url=os.environ.get("AIVEN_WEB_URL", "https://api.aiven.io"))
        self.client.set_auth_token(os.environ["AIVEN_AUTH_TOKEN"])
        self.project = os.environ.get("AIVEN_TEST_PROJECT", "test")
        self.service_specifications = self._discover_required_services()

    def spin_up_services(self):
        start = time.monotonic()
        with ThreadPool(processes=len(self.service_specifications)) as pool:
            services = pool.map(self._create_service, self.service_specifications)

        # If we created new services, sleep for a minute to allow them to settle.
        # Attempting to use them immediately after they transition to running
        # results in many transient errors caused by nodes not quite ready, DNS not
        # propagated, etc.
        new_services = time.monotonic() - start > 60
        if new_services:
            time.sleep(60)

        for service in services:
            service_name, service_type = service['service_name'], service['service_type']
            AivenExampleTest.services[service_type][service_name] = service

    def tear_down_services(self):
        for service in self.service_specifications:
            self.client.delete_service(self.project, service.name)

    def _discover_required_services(self):
        subclasses = self._gather_subclasses(AivenExampleTest)
        service_specifications = set()
        for subclass in subclasses:
            service_specifications.update(subclass.required_services)
        return service_specifications

    def _gather_subclasses(self, cls):
        all_subclasses = []
        for subclass in cls.__subclasses__():
            all_subclasses.append(subclass)
            all_subclasses.extend(self._gather_subclasses(subclass))
        return all_subclasses

    def _create_service(self, service_spec, timeout=600):
        start = time.monotonic()
        while time.monotonic() - start < timeout:
            service = self._get_service(self.project, service_spec)
            if service:
                return service
            time.sleep(5)
        raise TimeoutError("Creating service timed out after {} seconds".format(timeout))

    def _get_service(self, project, service_spec):
        try:
            service = self.client.get_service(project=project, service=service_spec.name)
            if service['state'] == 'RUNNING':
                return service
        except Error as e:
            if e.status != 404:
                raise
            self.client.create_service(
                project=self.project,
                service=service_spec.name,
                service_type=service_spec.type,
                plan=service_spec.plan,
                cloud=os.environ.get("AIVEN_TEST_CLOUD", "google-europe-west1"),
                user_config=None,
            )

class AivenExampleTest(unittest.TestCase):
    required_services = tuple()
    services = defaultdict(dict)
    _project_ca = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.client = AivenClient(base_url=os.environ.get("AIVEN_WEB_URL", "https://api.aiven.io"))
        self.client.set_auth_token(os.environ["AIVEN_AUTH_TOKEN"])
        self.project = os.environ.get("AIVEN_TEST_PROJECT", "test")

    def execute(self, command, **kwargs):
        return subprocess.run(shlex.split(command),
                              stderr=subprocess.PIPE,
                              stdout=subprocess.PIPE,
                              universal_newlines=True,
                              **kwargs)

    @property
    def project_ca(self):
        if self._project_ca is None:
            self._project_ca = self.client.get_project_ca(self.project)['certificate']
        return self._project_ca


def setup_module(*args, **kwargs):
    if not os.environ.get('AIVEN_AUTH_TOKEN'):
        pytest.exit("AIVEN_AUTH_TOKEN is required in env", returncode=1)

    with open("test-config.json") as f:
        config = json.load(f)
    install_dependencies(config)

    ServiceManager().spin_up_services()


def teardown_module(*args, **kwargs):
    if not os.environ.get("SKIP_TEARDOWN"):
        ServiceManager().tear_down_services()


def install_dependencies(config):
    commands = list()
    commands.extend([f"go get {dependency}" for dependency in config["go_dependencies"]])
    commands.extend([f"npm install --prefix {prefix}" for prefix in config["nodejs_dependencies"]])
    commands.extend(
        [f"python3 -m pip --disable-pip-version-check install {dependency}" for dependency in config["python_dependencies"]])
    with ThreadPool(processes=len(commands)) as pool:
        failures = list(filter(None, pool.map(execute, commands)))

    if failures:
        pytest.exit("\n".join(map(str, failures)), returncode=1)


def execute(command):
    try:
        subprocess.check_output(shlex.split(command), universal_newlines=True, stderr=subprocess.PIPE)
    except subprocess.CalledProcessError as e:
        return e
    except Exception as e:
        pytest.exit(f"Unexpected exception executing: '{command}' - {e}", returncode=1)
