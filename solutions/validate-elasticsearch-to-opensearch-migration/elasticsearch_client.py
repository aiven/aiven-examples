import argparse
import urllib3
from elasticsearch import Elasticsearch
from urllib.parse import urlparse

# Disable SSL warnings as we are not verifying the server certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def create_es_client(es_host, es_user=None, es_password=None):
    """
    Creates and returns an Elasticsearch client based on the given host and credentials.

    :param es_host: Elasticsearch host URL (e.g. https://localhost:9200)
    :param es_user: Optional Elasticsearch username
    :param es_password: Optional Elasticsearch password
    :return: Elasticsearch client
    """
    parsed_url = urlparse(es_host)
    scheme = parsed_url.scheme
    host = parsed_url.hostname
    port = parsed_url.port

    # Default to port 9200 if not specified
    if not port:
        port = 9200

    # Create Elasticsearch client with or without basic authentication
    if es_user and es_password:
        es = Elasticsearch(
            [f"{scheme}://{host}:{port}"],
            http_auth=(es_user, es_password),
            scheme=scheme,
            port=port,
            verify_certs=False,
        )
    else:
        es = Elasticsearch(
            [f"{scheme}://{host}:{port}"], scheme=scheme, port=port, verify_certs=False
        )

    print(f"Connecting to Elasticsearch at {scheme}://{host}:{port}...\n")
    return es


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Elasticsearch Cluster Checker")
    parser.add_argument(
        "--es_host",
        type=str,
        required=True,
        help="cluster host URL (e.g. https://localhost:9200)",
    )
    parser.add_argument(
        "--es_user", type=str, required=False, help="Elasticsearch username (optional)"
    )
    parser.add_argument(
        "--es_password",
        type=str,
        required=False,
        help="Elasticsearch password (optional)",
    )
    args = parser.parse_args()

    # Use the function to create the client
    es = create_es_client(args.es_host, args.es_user, args.es_password)
