# pip install elasticsearch==7.10.1 icecream
# mise use -g python@3.11
# python pre_snapshot_checks.py --es_host https://localhost:9200 --es_user admin --es_password admin
# python pre_snapshot_checks.py --es_host http://localhost:9200

import argparse
from elasticsearch import Elasticsearch
from elasticsearch.exceptions import ElasticsearchException
import urllib3
from urllib.parse import urlparse

issues = False


# if they are using ILM instead of ISM, we need to do some more work
def check_ilm(es):
    # TODO later
    return


# flattened type is not supported in OpenSearch
def check_no_flattened_type(es):
    # TODO later
    return


# check if xpack is enabled, and warm them so they double check they are not relying on some feature not available in OpenSearch
def check_xpack_disabled(es):
    # TODO later
    return


def check_indices_version(es):
    global issues
    try:
        # don't use include_type_name as it fails in OS
        # indices = es.indices.get('*', include_type_name=False)
        indices = es.indices.get("*")
        for index, details in indices.items():
            index_version = details["settings"]["index"]["version"]["created"]
            version_num = int(index_version[:3])
            # ES7.10: 7100299
            # Opendistro: 7100299
            # OS 1.2.4: 135238227
            # OS 2.15: 136367827
            # ic(index, index_version, version_num)
            if (version_num > 136 and version_num < 700) or version_num > 710:
                print(
                    f"\nIssue!! Index {index} was created with an unsupported version: {index_version}"
                )
                issues = True
    except ElasticsearchException as e:
        print(f"Error occurred while checking index versions: {str(e)}")


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

    parsed_url = urlparse(args.es_host)
    scheme = parsed_url.scheme
    host = parsed_url.hostname
    port = parsed_url.port
    # Default to port 9200 if not specified
    if not port:
        port = 9200

    # Disable SSL warnings as we are not verifying the server certificates
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    # Create Elasticsearch client with or without basic authentication
    if args.es_user and args.es_password:
        es = Elasticsearch(
            [f"{scheme}://{host}:{port}"],
            http_auth=(args.es_user, args.es_password),
            scheme=scheme,
            port=port,
            verify_certs=False,
        )
    else:
        es = Elasticsearch(
            [f"{scheme}://{host}:{port}"], scheme=scheme, port=port, verify_certs=False
        )

    print(f"Connecting to Elasticsearch at {scheme}://{host}:{port}...\n")
    print("\n------------------------------------------------------------")
    print("Starting checks.")

    check_indices_version(es)
    check_no_flattened_type(es)
    check_ilm(es)
    check_xpack_disabled(es)

    print("\n------------------------------------------------------------")
    print("Checks completed.")
    if issues:
        print("There are issues that need to be resolved before migrating.")
    else:
        print("No issues found.")
    print("------------------------------------------------------------")
