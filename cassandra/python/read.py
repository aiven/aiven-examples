import ssl
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider

host = "cassandra-3b8d4ed6-myfirstcloudhub.aivencloud.com"
port = 15193
auth_provider = PlainTextAuthProvider("avnadmin", "nr0dfnswz36xs9pi")
ssl_options = {"ca_certs": "ca.pem", "cert_reqs": ssl.CERT_REQUIRED}

with Cluster([host], port=port, ssl_options=ssl_options, auth_provider=auth_provider) as cluster:
    with cluster.connect() as session:
        session.execute("USE example_keyspace")
        for row in session.execute("SELECT id, message FROM example_table"):
            print("Row: id = {}, message = {}".format(row.id, row.message))
