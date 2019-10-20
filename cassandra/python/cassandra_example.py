# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

import ssl

from cassandra.auth import PlainTextAuthProvider
from cassandra.cluster import Cluster
from cassandra.policies import DCAwareRoundRobinPolicy


def cassandra_example(args):
    auth_provider = PlainTextAuthProvider(args.username, args.password)
    ssl_options = {"ca_certs": args.ca_path, "cert_reqs": ssl.CERT_REQUIRED}
    with Cluster([args.host], port=args.port, ssl_options=ssl_options, auth_provider=auth_provider,
                 load_balancing_policy=DCAwareRoundRobinPolicy(local_dc='aiven')) as cluster:
        with cluster.connect() as session:
            # Create a keyspace
            session.execute("""
                CREATE KEYSPACE IF NOT EXISTS example_keyspace
                WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'aiven': 3}
            """)

            # Create a table
            session.execute("""
                CREATE TABLE IF NOT EXISTS example_keyspace.example_table (
                    id int PRIMARY KEY,
                    message text
                )
            """)

            # Insert some data
            for i in range(10):
                session.execute("""
                    INSERT INTO example_keyspace.example_table (id, message)
                    VALUES (%s, %s)
                """, (i, "Hello world!"))

            # Read it back
            for row in session.execute("SELECT id, message FROM example_keyspace.example_table"):
                print("Row: id = {}, message = {}".format(row.id, row.message))
