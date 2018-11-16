import ssl
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

import cassandra

host = "cassandra-3b8d4ed6-myfirstcloudhub.aivencloud.com"
port = 15193
auth_provider = PlainTextAuthProvider("avnadmin", "nr0dfnswz36xs9pi")
ssl_options = {"ca_certs": "ca.pem", "cert_reqs": ssl.CERT_REQUIRED}

with Cluster([host], port=port, ssl_options=ssl_options, auth_provider=auth_provider) as cluster:
    with cluster.connect() as session:
        try:
            session.execute("CREATE KEYSPACE example_keyspace WITH REPLICATION = {'class': 'NetworkTopologyStrategy', 'aiven': 3}")
        except cassandra.AlreadyExists as ex:
            print(ex)
        session.execute("USE example_keyspace")
        try:
            session.execute("CREATE TABLE example_table (id int PRIMARY KEY, message text)")
        except cassandra.AlreadyExists as ex:
            print(ex)
        session.execute("INSERT INTO example_table (id, message) VALUES (%s, %s)", (123, "Hello world!"))
        print("Row inserted")
