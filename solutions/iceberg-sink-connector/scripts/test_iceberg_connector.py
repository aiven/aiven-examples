#!/usr/bin/env python3
"""
Iceberg Sink Connector Test Script (Terraform Integration)

This script tests the Iceberg sink connector by:
1. Reading configuration from Terraform outputs
2. Producing test messages to Kafka
3. Waiting for the Iceberg connector to process them
4. Querying the data from DuckDB

Usage:
    python test_iceberg_terraform.py
    python test_iceberg_terraform.py --verbose
"""

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import requests
import urllib3
import duckdb
import uuid
from datetime import datetime, timezone
from typing import Dict, Optional, Any

# Suppress SSL warnings for self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class Colors:
    """ANSI color codes for terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"  # No Color


class TerraformIcebergTest:
    """Main class for testing Iceberg sink connector with Terraform integration."""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.config = {}
        self.run_id = str(uuid.uuid4())
        self.session_headers = {
            "Content-Type": "application/json",
            "User-Agent": "IcebergTest/1.0",
        }

    def print_status(self, message: str) -> None:
        """Print a status message."""
        print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")

    def print_success(self, message: str) -> None:
        """Print a success message."""
        print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")

    def print_warning(self, message: str) -> None:
        """Print a warning message."""
        print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")

    def print_error(self, message: str) -> None:
        """Print an error message."""
        print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")

    def run_terraform_output_all(self) -> Dict[str, Any]:
        """Run terraform output command and return all outputs as a dictionary with sensitive info."""
        try:
            # Get the parent directory where Terraform files are located
            terraform_dir = Path(os.path.dirname(os.path.abspath(__file__))).parent

            result = subprocess.run(
                ["terraform", "output", "-json"],
                capture_output=True,
                text=True,
                check=True,
                cwd=terraform_dir,
            )
            outputs = json.loads(result.stdout)

            # Return the full output structure to preserve sensitive information
            return outputs
        except subprocess.CalledProcessError as e:
            self.print_error(f"Failed to get Terraform outputs: {e}")
            if self.verbose:
                print(f"STDOUT: {e.stdout}")
                print(f"STDERR: {e.stderr}")
            raise
        except json.JSONDecodeError as e:
            self.print_error(f"Failed to parse Terraform outputs JSON: {e}")
            raise

    def load_config_from_terraform(self) -> Dict[str, str]:
        """Load configuration from Terraform outputs."""
        self.print_status("Loading configuration from Terraform outputs...")

        try:
            # Get all outputs in one command
            terraform_outputs = self.run_terraform_output_all()

            # Get AWS credentials from environment
            aws_access_key_id = os.environ.get("AWS_ACCESS_KEY_ID")
            aws_secret_access_key = os.environ.get("AWS_SECRET_ACCESS_KEY")

            if not aws_access_key_id or not aws_secret_access_key:
                self.print_warning("AWS credentials not found in environment variables")
                self.print_warning(
                    "Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
                )

            config = {
                "KAFKA_URI": terraform_outputs.get("kafka_rest_uri", {}).get(
                    "value", ""
                ),
                "KAFKA_CONNECT_URI": terraform_outputs.get("kafka_connect_uri", {}).get(
                    "value", ""
                ),
                "S3_PATH": terraform_outputs.get("s3_warehouse_path", {}).get(
                    "value", ""
                ),
                "TOPIC_NAME": terraform_outputs.get("topic_name", {}).get("value", ""),
                "CONNECTOR_NAME": terraform_outputs.get("connector_name", {}).get(
                    "value", ""
                ),
                "TABLE_NAME": terraform_outputs.get("table_name", {}).get("value", ""),
                "AWS_REGION": terraform_outputs.get("aws_region", {}).get("value", ""),
                "AWS_ACCESS_KEY_ID": aws_access_key_id or "",
                "AWS_SECRET_ACCESS_KEY": aws_secret_access_key or "",
                "NUM_MESSAGES": "10",
            }

            # Validate that we have the required outputs
            missing_outputs = [
                key
                for key, value in config.items()
                if key
                not in ["AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "NUM_MESSAGES"]
                and not value
            ]

            if missing_outputs:
                raise ValueError(
                    f"Missing required Terraform outputs: {', '.join(missing_outputs)}"
                )

            self.print_success("Configuration loaded successfully")
            if self.verbose:
                print("Terraform outputs:")
                for key, output_data in terraform_outputs.items():
                    value = output_data.get("value", "")
                    is_sensitive = output_data.get("sensitive", False)
                    print(
                        f"  {key}: {self._redact_sensitive_value(value, is_sensitive)}"
                    )
                print("\nProcessed configuration:")
                for key, value in config.items():
                    is_sensitive = "SECRET" in key or "PASSWORD" in key
                    print(
                        f"  {key}: {self._redact_sensitive_value(value, is_sensitive)}"
                    )

            return config

        except Exception as e:
            self.print_error(f"Failed to load configuration: {e}")
            raise

    def _redact_sensitive_value(
        self, value: str, is_sensitive_key: bool = False
    ) -> str:
        """Redact sensitive parts of a value while preserving the structure."""
        if not isinstance(value, str):
            return value

        # If the key itself is sensitive, replace entire value with asterisks
        if is_sensitive_key:
            return "*" * len(value)

        # Otherwise, replace any Aiven password occurrences within the value
        import re

        # Pattern to match Aiven passwords (AVNS_ followed by alphanumeric characters and underscores)
        aiven_password_pattern = r"AVNS_[a-zA-Z0-9_]+"

        # Replace all Aiven password occurrences with asterisks
        redacted_value = re.sub(
            aiven_password_pattern, lambda m: "*" * len(m.group()), value
        )

        return redacted_value

    def make_request(
        self,
        url: str,
        method: str = "GET",
        data: Optional[Dict] = None,
        headers: Optional[Dict] = None,
    ) -> Dict:
        """Make HTTP request using requests."""
        request_headers = self.session_headers.copy()
        if headers:
            request_headers.update(headers)

        if self.verbose:
            redacted_url = self._redact_sensitive_value(url, False)
            self.print_status(f"Making {method} request to: {redacted_url}")

        try:
            # Disable SSL verification for self-signed certificates
            if method.upper() == "GET":
                response = requests.get(
                    url, headers=request_headers, timeout=30, verify=False
                )
            elif method.upper() == "POST":
                response = requests.post(
                    url, headers=request_headers, json=data, timeout=30, verify=False
                )
            else:
                raise ValueError(f"Unsupported HTTP method: {method}")

            response.raise_for_status()

            if response.text:
                return response.json()
            return {}

        except requests.exceptions.HTTPError as e:
            if self.verbose:
                self.print_error(
                    f"HTTP Error {e.response.status_code}: {e.response.text}"
                )
            raise
        except requests.exceptions.RequestException as e:
            self.print_error(f"Request Error: {e}")
            raise
        except json.JSONDecodeError as e:
            self.print_error(f"JSON Decode Error: {e}")
            raise

    def wait_for_service(self, service_uri: str, max_attempts: int = 30) -> bool:
        """Wait for a service to be ready."""
        redacted_uri = self._redact_sensitive_value(service_uri, False)
        self.print_status(f"Waiting for service to be ready: {redacted_uri}")

        for attempt in range(1, max_attempts + 1):
            try:
                # For other services, try to parse JSON response
                self.make_request(service_uri)
                self.print_success("Service is ready!")
                return True
            except (
                requests.exceptions.HTTPError,
                requests.exceptions.RequestException,
                json.JSONDecodeError,
            ):
                pass

            self.print_status(
                f"Attempt {attempt}/{max_attempts} - Service not ready yet, waiting..."
            )
            time.sleep(10)

        self.print_error(
            f"Service failed to become ready after {max_attempts} attempts"
        )
        return False

    def check_connector_status(self, connect_uri: str, connector_name: str) -> bool:
        """Check if the connector is running."""
        self.print_status(f"Checking connector status: {connector_name}")

        try:
            url = f"{connect_uri}/connectors/{connector_name}/status"
            data = self.make_request(url)

            state = data.get("connector", {}).get("state")

            if state == "RUNNING":
                self.print_success(f"Connector {connector_name} is running")
                return True
            else:
                self.print_error(
                    f"Connector {connector_name} is not running (status: {state})"
                )
                return False

        except Exception as e:
            self.print_error(f"Failed to check connector status: {e}")
            return False

    def produce_test_messages(
        self, kafka_uri: str, topic_name: str, num_messages: int = 10
    ) -> bool:
        """Produce test messages to Kafka using REST API."""
        self.print_status(
            f"Producing {num_messages} test messages to topic: {topic_name}"
        )

        # Generate test messages
        messages = []
        for i in range(1, num_messages + 1):
            message = {
                "key": f"key-{i}",
                "value": {
                    "test_field": i,
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "message": f"Test message {i}",
                    "user_id": f"user_{i % 5}",
                    "category": f"category_{i % 3}",
                    "run_id": self.run_id,
                },
            }
            messages.append(message)

        try:
            url = f"{kafka_uri}/topics/{topic_name}"
            headers = {
                "Content-Type": "application/vnd.kafka.json.v2+json",
                "Accept": "application/vnd.kafka.v2+json",
            }

            # Send messages in batches
            batch_size = 5
            for i in range(0, len(messages), batch_size):
                batch = messages[i : i + batch_size]
                payload = {"records": batch}

                self.make_request(url, method="POST", data=payload, headers=headers)
                self.print_status(
                    f"Sent batch {i // batch_size + 1}/{(len(messages) + batch_size - 1) // batch_size}"
                )

            self.print_success(f"Produced {num_messages} test messages")
            return True

        except Exception as e:
            self.print_error(f"Failed to produce messages via REST API: {e}")
            self.print_warning("You may need to use kafka-console-producer directly")
            return False

    def wait_for_data_in_duckdb(
        self,
        s3_path: str,
        aws_access_key: str,
        aws_secret_key: str,
        aws_region: str,
        expected_count: int = 10,
        max_attempts: int = 30,
    ) -> bool:
        """Wait for data to appear in DuckDB by querying the Iceberg table."""
        self.print_status(
            f"Waiting for data to appear in DuckDB (expecting {expected_count} records)... This can take a couple of minutes..."
        )

        # Get table name from config
        table_name = self.config.get("TABLE_NAME", "test-table")

        # Configure DuckDB with AWS credentials
        con = duckdb.connect(":memory:")

        # Load the Iceberg extension
        con.execute("INSTALL iceberg")
        con.execute("LOAD iceberg")

        # Enable version guessing for Iceberg tables
        con.execute("SET unsafe_enable_version_guessing = true")

        # Set up AWS credentials and region for S3 access
        if aws_access_key and aws_secret_key:
            con.execute(f"SET s3_access_key_id='{aws_access_key}'")
            con.execute(f"SET s3_secret_access_key='{aws_secret_key}'")
        if aws_region:
            con.execute(f"SET s3_region='{aws_region}'")

        # Extract bucket and prefix from S3 path
        s3_path_clean = s3_path.replace("s3://", "").rstrip("/")
        if "/" in s3_path_clean:
            bucket, prefix = s3_path_clean.split("/", 1)
        else:
            bucket = s3_path_clean
            prefix = ""

        for attempt in range(1, max_attempts + 1):
            try:
                # Query the Iceberg table using DuckDB's Iceberg support
                query = f"""
                SELECT COUNT(*) AS count 
                FROM iceberg_scan('s3://{bucket}/{prefix}/{table_name}', allow_moved_paths = true)
                WHERE run_id = '{self.run_id}'
                """
                result = con.execute(query).fetchone()

                if result and result[0] >= expected_count:
                    self.print_success(
                        f"Found {result[0]} records in DuckDB (expected: {expected_count})"
                    )
                    con.close()
                    return True
                elif result:
                    self.print_status(
                        f"Attempt {attempt}/{max_attempts} - Found {result[0]} records, waiting for more..."
                    )
                else:
                    self.print_status(
                        f"Attempt {attempt}/{max_attempts} - No data found yet..."
                    )
                time.sleep(30)
            except Exception as e:
                self.print_warning(
                    f"Attempt {attempt}/{max_attempts} - Error querying DuckDB: {e}"
                )
                time.sleep(30)

        con.close()
        self.print_error(
            f"Failed to find expected data in DuckDB after {max_attempts} attempts"
        )
        return False

    def query_duckdb_data(
        self,
        s3_path: str,
        aws_access_key: str,
        aws_secret_key: str,
        aws_region: str,
        limit: int = 10,
    ) -> bool:
        """Query and display data from DuckDB by reading the Iceberg table."""
        self.print_status("Querying data from DuckDB...")

        # Get table name from config
        table_name = self.config.get("TABLE_NAME", "test-table")

        # Configure DuckDB with AWS credentials
        con = duckdb.connect(":memory:")

        # Load the Iceberg extension
        con.execute("INSTALL iceberg")
        con.execute("LOAD iceberg")

        # Enable version guessing for Iceberg tables
        con.execute("SET unsafe_enable_version_guessing = true")

        # Set up AWS credentials and region for S3 access
        if aws_access_key and aws_secret_key:
            con.execute(f"SET s3_access_key_id='{aws_access_key}'")
            con.execute(f"SET s3_secret_access_key='{aws_secret_key}'")
        if aws_region:
            con.execute(f"SET s3_region='{aws_region}'")

        # Extract bucket and prefix from S3 path
        s3_path_clean = s3_path.replace("s3://", "").rstrip("/")
        if "/" in s3_path_clean:
            bucket, prefix = s3_path_clean.split("/", 1)
        else:
            bucket = s3_path_clean
            prefix = ""

        try:
            # Query the Iceberg table using DuckDB's Iceberg support
            query = f"""
            SELECT * 
            FROM iceberg_scan('s3://{bucket}/{prefix}/{table_name}', allow_moved_paths = true)
            WHERE run_id = '{self.run_id}'
            LIMIT {limit}
            """
            result = con.execute(query).fetchall()

            self.print_success(f"Data from Iceberg table '{table_name}':")
            if result:
                # Get column names
                columns = [desc[0] for desc in con.description]
                print(f"  Columns: {columns}")
                for row in result:
                    print(f"  {row}")
            else:
                print("  No data found in the table")

            con.close()
            return True
        except Exception as e:
            self.print_error(f"Failed to query DuckDB: {e}")
            con.close()
            return False

    def show_connector_metrics(self, connect_uri: str, connector_name: str) -> None:
        """Display connector metrics."""
        self.print_status(f"Connector metrics for: {connector_name}")

        try:
            # Get connector status
            status_url = f"{connect_uri}/connectors/{connector_name}/status"
            status_data = self.make_request(status_url)

            print("Connector Status:")
            print(json.dumps(status_data, indent=2))

            # Get connector config
            config_url = f"{connect_uri}/connectors/{connector_name}/config"
            config_data = self.make_request(config_url)

            print("\nConnector Configuration:")
            # Hide sensitive information
            safe_config = {}
            for key, value in config_data.items():
                is_sensitive = any(
                    sensitive in key.lower()
                    for sensitive in ["password", "secret", "key"]
                )
                safe_config[key] = self._redact_sensitive_value(value, is_sensitive)
            print(json.dumps(safe_config, indent=2))

        except Exception as e:
            self.print_error(f"Failed to get connector metrics: {e}")

    def run_workflow(self) -> bool:
        """Run the complete test workflow."""
        self.print_status(
            f"Starting Iceberg Sink Connector Test Workflow (Run ID: {self.run_id})"
        )

        # Load configuration from Terraform
        self.config = self.load_config_from_terraform()

        # Wait for services to be ready
        if not self.wait_for_service(self.config["KAFKA_CONNECT_URI"]):
            return False

        # Check connector status
        if not self.check_connector_status(
            self.config["KAFKA_CONNECT_URI"], self.config["CONNECTOR_NAME"]
        ):
            return False

        # Show initial connector metrics
        self.show_connector_metrics(
            self.config["KAFKA_CONNECT_URI"], self.config["CONNECTOR_NAME"]
        )

        # Produce test messages
        num_messages = int(self.config.get("NUM_MESSAGES", "10"))
        if not self.produce_test_messages(
            self.config["KAFKA_URI"], self.config["TOPIC_NAME"], num_messages
        ):
            return False

        # Wait for data to appear in DuckDB
        expected_count = int(self.config.get("NUM_MESSAGES", "10"))
        if not self.wait_for_data_in_duckdb(
            self.config["S3_PATH"],
            self.config["AWS_ACCESS_KEY_ID"],
            self.config["AWS_SECRET_ACCESS_KEY"],
            self.config["AWS_REGION"],
            expected_count,
        ):
            return False

        # Query and display the data
        if not self.query_duckdb_data(
            self.config["S3_PATH"],
            self.config["AWS_ACCESS_KEY_ID"],
            self.config["AWS_SECRET_ACCESS_KEY"],
            self.config["AWS_REGION"],
        ):
            return False

        # Show final connector metrics
        self.show_connector_metrics(
            self.config["KAFKA_CONNECT_URI"], self.config["CONNECTOR_NAME"]
        )

        self.print_success(
            "Iceberg Sink Connector Test Workflow completed successfully!"
        )
        return True


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Test Iceberg Sink Connector with Terraform Integration",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    python test_iceberg_terraform.py
    python test_iceberg_terraform.py --verbose
        """,
    )

    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose output"
    )

    args = parser.parse_args()

    try:
        # Run the workflow
        workflow = TerraformIcebergTest(verbose=args.verbose)
        success = workflow.run_workflow()

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        print(f"\n{Colors.YELLOW}[WARNING]{Colors.NC} Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"{Colors.RED}[ERROR]{Colors.NC} {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
