#!/usr/bin/env python3
"""
Test script for Debezium diskless replication.
Creates a table, inserts rows, and consumes messages from Kafka topic.
"""
import subprocess
import threading
import time
import json
import psycopg2
from confluent_kafka import Consumer, KafkaError, KafkaException
import os
import tempfile
import shutil
import sys
import uuid
import argparse


def get_terraform_output(output_name):
    """Get a Terraform output value."""
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            capture_output=True,
            text=True,
            check=True,
            cwd=os.path.dirname(os.path.abspath(__file__)),
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(
            f"Error getting Terraform output '{output_name}': {e.stderr}",
            file=sys.stderr,
        )
        sys.exit(1)


def create_certificate_files(ca_cert, access_cert, access_key, cert_dir):
    """Create certificate files from Terraform outputs."""
    try:
        ca_path = os.path.join(cert_dir, "ca.pem")
        cert_path = os.path.join(cert_dir, "service.cert")
        key_path = os.path.join(cert_dir, "service.key")

        # Write CA certificate
        with open(ca_path, "w") as f:
            f.write(ca_cert)

        # Write access certificate
        with open(cert_path, "w") as f:
            f.write(access_cert)

        # Write access key
        with open(key_path, "w") as f:
            f.write(access_key)

        # Set appropriate permissions for the key file
        os.chmod(key_path, 0o600)

        print(f"✅ Certificate files created in {cert_dir}")
        return True
    except Exception as e:
        print(f"Error creating certificate files: {e}", file=sys.stderr)
        return False


def producer_thread(
    postgres_uri,
    table_name,
    num_rows=1000,
    run_id=None,
    inserted_ids=None,
    batch_size=100,
):
    """Thread that creates the table and inserts test data."""
    print(f"[Producer] Starting producer thread...")
    if run_id:
        print(f"[Producer] Run ID: {run_id}")

    try:
        # Connect to PostgreSQL
        conn = psycopg2.connect(postgres_uri)
        cursor = conn.cursor()

        # Define required columns
        # Format: column_name -> (column_definition_for_create, column_definition_for_alter)
        # For CREATE TABLE, we include PRIMARY KEY on id
        # For ALTER TABLE, we exclude PRIMARY KEY since it can't be added to existing tables
        required_columns = {
            "id": ("SERIAL PRIMARY KEY", "SERIAL"),
            "name": ("VARCHAR(100)", "VARCHAR(100)"),
            "value": ("INTEGER", "INTEGER"),
            "test_run_id": ("VARCHAR(100)", "VARCHAR(100)"),
            "created_at": (
                "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
                "TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
            ),
        }

        # Create table if it doesn't exist
        print(f"[Producer] Creating table '{table_name}' if it doesn't exist...")
        column_definitions = [
            f"{col_name} {col_def[0]}" for col_name, col_def in required_columns.items()
        ]
        create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            {', '.join(column_definitions)}
        );
        """
        cursor.execute(create_table_sql)
        conn.commit()

        # Check and add missing columns
        print(f"[Producer] Checking for missing columns...")
        cursor.execute(
            f"""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = '{table_name}'
        """
        )
        existing_columns = {row[0] for row in cursor.fetchall()}

        missing_columns = []
        for col_name, (create_def, alter_def) in required_columns.items():
            if col_name not in existing_columns:
                missing_columns.append((col_name, alter_def))

        if missing_columns:
            print(
                f"[Producer] Found {len(missing_columns)} missing column(s), adding them..."
            )
            for col_name, col_def in missing_columns:
                # Handle special case for id column - can't easily add SERIAL PRIMARY KEY to existing table
                if col_name == "id" and existing_columns:
                    print(
                        f"[Producer] ⚠️  Skipping 'id' column (table already exists, PRIMARY KEY can't be added)"
                    )
                    continue

                # Build ALTER TABLE statement using the alter_def
                alter_sql = f"ALTER TABLE {table_name} ADD COLUMN {col_name} {col_def}"

                try:
                    cursor.execute(alter_sql)
                    print(f"[Producer] ✅ Added column '{col_name}'")
                except Exception as e:
                    error_msg = str(e)
                    if (
                        "already exists" in error_msg.lower()
                        or "duplicate" in error_msg.lower()
                    ):
                        print(
                            f"[Producer] ⚠️  Column '{col_name}' already exists (race condition?)"
                        )
                    else:
                        print(f"[Producer] ⚠️  Could not add column '{col_name}': {e}")

            conn.commit()
            print(f"[Producer] ✅ Table schema updated")
        else:
            print(f"[Producer] ✅ All required columns exist")

        print(f"[Producer] ✅ Table '{table_name}' ready")

        # Wait a bit for Debezium to detect the table
        time.sleep(2)

        # Insert test data with unique run ID
        print(f"[Producer] Inserting {num_rows} rows with run_id '{run_id}'...")
        insert_sql = f"INSERT INTO {table_name} (name, value, test_run_id) VALUES (%s, %s, %s) RETURNING id"

        inserted_ids_list = []
        for i in range(1, num_rows + 1):
            cursor.execute(insert_sql, (f"test_record_{i}", i * 10, run_id))
            row_id = cursor.fetchone()[0]
            inserted_ids_list.append(row_id)
            if i % batch_size == 0:
                conn.commit()
                print(f"[Producer] Inserted {i}/{num_rows} rows...")

        conn.commit()

        # Store inserted IDs in shared structure
        if inserted_ids is not None:
            inserted_ids.update(inserted_ids_list)

        print(f"[Producer] ✅ All {num_rows} rows inserted successfully")

        cursor.close()
        conn.close()

    except Exception as e:
        print(f"[Producer] ❌ Error: {e}", file=sys.stderr)
        raise


def consumer_thread(
    kafka_uri,
    topic_name,
    cert_dir,
    num_messages=1000,
    run_id=None,
    expected_ids=None,
    received_ids=None,
):
    """Thread that consumes messages from Kafka topic."""
    print(f"[Consumer] Starting consumer thread...")
    if run_id:
        print(f"[Consumer] Looking for messages with run_id: {run_id}")

    ca_path = os.path.join(cert_dir, "ca.pem")
    cert_path = os.path.join(cert_dir, "service.cert")
    key_path = os.path.join(cert_dir, "service.key")

    # Verify certificates exist
    for cert_file in [ca_path, cert_path, key_path]:
        if not os.path.exists(cert_file):
            print(
                f"[Consumer] ❌ Certificate file not found: {cert_file}",
                file=sys.stderr,
            )
            return

    try:
        # Configure Confluent Kafka consumer
        config = {
            "bootstrap.servers": kafka_uri,
            "group.id": f'debezium-test-consumer-{run_id or "default"}',
            "auto.offset.reset": "latest",  # Start from latest messages, not from beginning
            "security.protocol": "ssl",
            "ssl.ca.location": ca_path,
            "ssl.certificate.location": cert_path,
            "ssl.key.location": key_path,
            "enable.auto.commit": False,  # Manual commit for better control
        }

        # Create Kafka consumer
        consumer = Consumer(config)

        print(f"[Consumer] ✅ Connected to Kafka")

        # Wait until the topic exists (Debezium may auto-create with delay)
        topic_wait_timeout = 180  # seconds
        poll_interval = 2  # seconds
        deadline = time.time() + topic_wait_timeout
        print(
            f"[Consumer] ⏳ Waiting for topic '{topic_name}' to be created (up to {topic_wait_timeout}s)..."
        )
        while True:
            try:
                md = consumer.list_topics(topic=topic_name, timeout=5.0)
                tmd = md.topics.get(topic_name)
                if tmd is not None and getattr(tmd, "error", None) is None and len(tmd.partitions) > 0:
                    print(
                        f"[Consumer] ✅ Topic '{topic_name}' is available with {len(tmd.partitions)} partition(s)."
                    )
                    break
            except Exception:
                # Treat any transient error as topic-not-ready and retry
                pass

            if time.time() >= deadline:
                raise TimeoutError(
                    f"Topic '{topic_name}' not found/ready after {topic_wait_timeout}s"
                )
            time.sleep(poll_interval)

        print(f"[Consumer] Subscribing to topic '{topic_name}'...")
        consumer.subscribe([topic_name])

        message_count = 0
        start_time = time.time()
        last_message_time = time.time()
        no_message_timeout = 120  # 2 minutes without messages

        print(f"[Consumer] Waiting for messages from topic '{topic_name}'...")

        while message_count < num_messages:
            # Poll for messages (timeout in seconds for confluent-kafka)
            msg = consumer.poll(timeout=1.0)

            if msg is None:
                # No message received
                elapsed_since_last = time.time() - last_message_time
                if elapsed_since_last > no_message_timeout:
                    print(
                        f"[Consumer] ⚠️  No messages received for {elapsed_since_last:.0f} seconds, stopping..."
                    )
                    break
                continue

            # Check for errors
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    # End of partition - not an error, just no more messages
                    continue
                else:
                    print(
                        f"[Consumer] ❌ Consumer error: {msg.error()}", file=sys.stderr
                    )
                    break

            last_message_time = time.time()

            try:
                # Decode message value
                value = msg.value()
                if value is None:
                    print(f"[Consumer] ⚠️  Message has no value")
                    continue

                # Parse JSON
                try:
                    message_data = json.loads(value.decode("utf-8"))
                except (json.JSONDecodeError, UnicodeDecodeError) as e:
                    print(f"[Consumer] ⚠️  Could not decode message: {e}")
                    continue

                # Debezium messages have a specific structure
                if not isinstance(message_data, dict):
                    print(
                        f"[Consumer] ⚠️  Message value is not a dict: {type(message_data)}"
                    )
                    continue

                # Debezium messages can have two formats:
                # 1. With payload wrapper: {"payload": {"op": "...", "after": {...}}}
                # 2. Direct format: {"op": "...", "after": {...}}
                # Check for payload wrapper first, then fall back to direct format
                if "payload" in message_data:
                    payload = message_data.get("payload", {})
                else:
                    # Message is already in the payload format
                    payload = message_data

                if not payload:
                    print(
                        f"[Consumer] ⚠️  Empty payload in message: {list(message_data.keys())}"
                    )
                    continue

                op = payload.get("op", "")

                # Count only INSERT operations (c=create, r=read/snapshot)
                if op in ("c", "r"):
                    after = payload.get("after", {})
                    msg_id = after.get("id")
                    msg_run_id = after.get("test_run_id")

                    # Only count messages from this test run
                    if run_id and msg_run_id != run_id:
                        print(
                            f"[Consumer] Skipping message id={msg_id} (run_id={msg_run_id} != {run_id})"
                        )
                        consumer.commit(msg)
                        continue

                    message_count += 1
                    print(
                        f"[Consumer] ✅ Received message {message_count}/{num_messages}: id={msg_id}, name={after.get('name')}, value={after.get('value')}, run_id={msg_run_id}"
                    )

                    # Track received IDs
                    if received_ids is not None and msg_id is not None:
                        received_ids.add(msg_id)

                    if message_count >= num_messages:
                        elapsed = time.time() - start_time
                        print(
                            f"[Consumer] ✅ Received all {num_messages} messages in {elapsed:.2f} seconds"
                        )
                        break
                else:
                    print(f"[Consumer] Skipping message with op='{op}' (not an insert)")

                # Commit offset after processing
                consumer.commit(msg)

            except Exception as e:
                print(f"[Consumer] ⚠️  Error processing message: {e}")
                import traceback

                traceback.print_exc()
                continue

        consumer.close()

        # Verify all expected messages were received
        if expected_ids is not None and received_ids is not None:
            expected_set = set(expected_ids)
            received_set = received_ids
            missing = expected_set - received_set
            extra = received_set - expected_set

            print(f"\n[Consumer] 📊 Message Verification:")
            print(f"[Consumer]   Expected IDs: {len(expected_set)}")
            print(f"[Consumer]   Received IDs: {len(received_set)}")

            if missing:
                print(f"[Consumer]   ⚠️  Missing IDs: {sorted(missing)}")
            if extra:
                print(f"[Consumer]   ⚠️  Extra IDs (not from this run): {sorted(extra)}")

            if not missing and not extra:
                print(f"[Consumer]   ✅ All expected messages received!")
            elif missing:
                print(f"[Consumer]   ❌ Missing {len(missing)} message(s)")

        if message_count < num_messages:
            print(
                f"[Consumer] ⚠️  Only received {message_count}/{num_messages} messages",
                file=sys.stderr,
            )

    except KafkaException as e:
        print(f"[Consumer] ❌ Kafka error: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc()
        raise
    except Exception as e:
        print(f"[Consumer] ❌ Error: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc()
        raise


def main():
    """Main function to run the test."""
    # Parse command line arguments
    parser = argparse.ArgumentParser(
        description="Test script for Debezium diskless replication",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-n",
        "--num-messages",
        type=int,
        default=500,
        help="Number of messages to insert and consume (default: 500)",
    )
    parser.add_argument(
        "-b",
        "--batch-size",
        type=int,
        default=100,
        help="Batch size for database commits (default: 100)",
    )
    args = parser.parse_args()
    num_messages = args.num_messages
    batch_size = args.batch_size

    print("=" * 60)
    print("Debezium Diskless Replication Test")
    print("=" * 60)
    print(f"Number of messages: {num_messages}")
    print(f"Batch size: {batch_size}")

    # Get configuration from Terraform outputs
    print("\n📋 Reading Terraform outputs...")
    postgres_uri = get_terraform_output("postgres_service_uri")
    kafka_uri = get_terraform_output("kafka_service_uri")
    topic_name = get_terraform_output("topic_name")
    table_name = get_terraform_output("table_name")

    # Get certificate information from Terraform outputs
    kafka_ca_cert = get_terraform_output("kafka_ca_cert")
    kafka_certificate = get_terraform_output("kafka_certificate")
    kafka_access_key = get_terraform_output("kafka_access_key")

    print(
        f"  PostgreSQL URI: {postgres_uri.split('@')[1] if '@' in postgres_uri else '***'}"
    )
    print(f"  Kafka URI: {kafka_uri.split('@')[1] if '@' in kafka_uri else '***'}")
    print(f"  Topic: {topic_name}")
    print(f"  Table: {table_name}")

    # Create temporary directory for certificates
    cert_dir = tempfile.mkdtemp(prefix="kafka-certs-")
    print(f"\n📝 Creating certificate files from Terraform outputs...")

    if not create_certificate_files(
        kafka_ca_cert, kafka_certificate, kafka_access_key, cert_dir
    ):
        print("Failed to create certificate files. Exiting.", file=sys.stderr)
        shutil.rmtree(cert_dir, ignore_errors=True)
        sys.exit(1)

    try:
        # Generate unique run ID for this test run
        run_id = str(uuid.uuid4())
        print(f"\n🆔 Test Run ID: {run_id}")

        # Shared data structures for tracking messages
        inserted_ids = set()
        received_ids = set()

        # Start consumer thread first (it will wait for messages)
        print(f"\n🚀 Starting threads...")
        consumer = threading.Thread(
            target=consumer_thread,
            args=(
                kafka_uri,
                topic_name,
                cert_dir,
                num_messages,
                run_id,
                inserted_ids,
                received_ids,
            ),
            daemon=False,
        )
        consumer.start()

        # Give consumer a moment to connect
        time.sleep(2)

        # Start producer thread
        producer = threading.Thread(
            target=producer_thread,
            args=(
                postgres_uri,
                table_name,
                num_messages,
                run_id,
                inserted_ids,
                batch_size,
            ),
            daemon=False,
        )
        producer.start()

        # Wait for both threads to complete
        print("\n⏳ Waiting for threads to complete...")
        producer.join()
        consumer.join(timeout=120)  # 2 minute timeout for consumer

        if consumer.is_alive():
            print(
                "\n⚠️  Consumer thread is still running (may be waiting for more messages)"
            )

        # Final verification
        print("\n" + "=" * 60)
        print("📊 Final Verification")
        print("=" * 60)
        if inserted_ids and received_ids:
            expected_set = inserted_ids
            received_set = received_ids
            missing = expected_set - received_set
            extra = received_set - expected_set

            print(f"Expected message IDs: {len(expected_set)}")
            print(f"Received message IDs: {len(received_set)}")

            if missing:
                print(f"❌ Missing {len(missing)} message(s): {sorted(missing)}")
            if extra:
                print(
                    f"⚠️  Extra {len(extra)} message(s) (from other runs): {sorted(extra)}"
                )

            if not missing and not extra:
                print("✅ All messages from this run were successfully received!")
            elif missing:
                print(f"❌ Test incomplete: {len(missing)} message(s) missing")

        print("\n" + "=" * 60)
        print("✅ Test completed!")
        print("=" * 60)

    except KeyboardInterrupt:
        print("\n\n⚠️  Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Test failed: {e}", file=sys.stderr)
        import traceback

        traceback.print_exc()
        sys.exit(1)
    finally:
        # Clean up certificates
        print(f"\n🧹 Cleaning up certificates...")
        shutil.rmtree(cert_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
