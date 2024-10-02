"""
This script connects to an Elasticsearch cluster to gather information about specific indices that match provided patterns. It gets key details like document count, aliases, and ISM (Index State Management) policies. It also tries to record any active indexing into the indices.

All this information is later used by another script to validate a migration.

Command Line Arguments
--patterns: A comma-separated list of patterns (wildcards supported) to filter indices. Example: "security*,logs*"
--waitsec: The number of seconds to wait between document count checks.
--outfile: Path to the JSON output file where collected data will be saved.
--es_host: The Elasticsearch cluster host (e.g., https://localhost:9200).
--es_user: (Optional) Username for Elasticsearch authentication.
--es_password: (Optional) Password for Elasticsearch authentication.json

Script Usage

You can run the script with the following command:

python get_migration_validation_data.py --patterns "<pattern>" --waitsec <seconds> --outfile <output file> --es_host <Elasticsearch Host URL> --es_user <username> --es_password <password>

Example Commands

python get_migration_validation_data.py --patterns "*" --waitsec 10 --outfile data1.json --es_host https://localhost:9200 --es_user admin --es_password admin

python get_migration_validation_data.py --patterns "security*,logs*" --waitsec 5 --outfile data1.json --es_host https://localhost:9200 --es_user admin --es_password admin

It has been tested with python 3.11
To install dependencies:
pip install elasticsearch==7.10.1 icecream rich

"""

from elasticsearch_client import create_es_client
import argparse
import json
import time
from elasticsearch.exceptions import ElasticsearchException
from datetime import datetime
from fnmatch import fnmatch


def get_matching_indices(es, patterns):
    try:
        all_indices = es.indices.get("*")
        matching_indices = []
        for pattern in patterns:
            matching_indices.extend(
                [index for index in all_indices if fnmatch(index, pattern)]
            )
        return matching_indices
    except ElasticsearchException as e:
        print(f"Error occurred while fetching matching indices: {str(e)}")
        return []


def get_index_doc_count(es, index):
    try:
        stats = es.indices.stats(index=index)
        return stats["_all"]["primaries"]["docs"]["count"]
    except ElasticsearchException as e:
        print(f"Error occurred while fetching doc count for index {index}: {str(e)}")
        return None


def get_ism_policy(es, index):
    try:
        index_settings = es.transport.perform_request(
            # _plugins for OS...
            # 'GET', f'/_plugins/_ism/explain/{index}',
            # _opendistro for ODFE
            "GET",
            f"/_opendistro/_ism/explain/{index}",
        )
        # ic(index, index_settings)
        policy_id = index_settings[index].get(
            "index.plugins.index_state_management.policy_id"
        ) or index_settings[index].get(
            "index.opendistro.index_state_management.policy_id"
        )
        if policy_id:
            return policy_id
        else:
            return None
    except Exception as e:
        return f"Error retrieving ISM policy ID: {str(e)}"


# def get_ism_policy(es, index):
#     try:
#         index_settings = es.indices.get_settings(index=index)
#         policy_id = (
#             index_settings[index]['settings']
#             .get('index.plugins.index_state_management.policy_id') or
#             index_settings[index]['settings']
#             .get('index.opendistro.index_state_management.policy_id')
#         )
#         if policy_id:
#             return policy_id
#         else:
#             return None
#     except Exception as e:
#         return f"Error retrieving ISM policy ID: {str(e)}"


def get_aliases(es, index):
    try:
        aliases = es.indices.get_alias(index=index)
        return aliases.get(index, {}).get("aliases", {})
    except ElasticsearchException as e:
        print(f"Error occurred while fetching aliases for index {index}: {str(e)}")
        return None


def collect_index_info(es, index):
    index_info = {
        "aliases": get_aliases(es, index),
        "ism_policy": get_ism_policy(es, index),
        "document_count": get_index_doc_count(es, index),
    }
    return dict(sorted(index_info.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Elasticsearch Cluster Checker")
    parser.add_argument(
        "--patterns",
        type=str,
        required=True,
        help="Comma-separated list of index name patterns (supports wildcards)",
    )
    parser.add_argument(
        "--waitsec",
        type=str,
        required=True,
        help="seconds to wait between doc count checks",
    )
    parser.add_argument(
        "--outfile", type=str, required=True, help="output file with the info"
    )
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
    waitsec = int(args.waitsec)

    # Use the function to create the client
    es = create_es_client(args.es_host, args.es_user, args.es_password)

    # Parse the comma-separated list of patterns
    patterns = [pattern.strip() for pattern in args.patterns.split(",")]

    # Collect information for all matching indices
    index_data = {}
    matching_indices = get_matching_indices(es, patterns)

    for index in matching_indices:
        print(f"Collecting info for index: {index}")
        index_data[index] = collect_index_info(es, index)

    # wait for the specified time
    print(f"Waiting for: {waitsec} seconds before checking doc count again")
    time.sleep(waitsec)

    # second pass for docs count
    for index in matching_indices:
        print(f"Collecting info for index: {index}")
        index_data[index]["document_count2"] = get_index_doc_count(es, index)
        if index_data[index]["document_count2"] != index_data[index]["document_count"]:
            index_data[index]["document_count_delta"] = True
        else:
            index_data[index]["document_count_delta"] = False
        # has a write alias?
        has_write_alias = any(
            alias.get("is_write_index", False)
            for alias in index_data[index]["aliases"].values()
        )
        index_data[index]["has_write_alias"] = has_write_alias

    # Prepare the final output structure
    output_data = {
        "cluster_url": f"{args.es_host}",
        "data_collected_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "waitsec": f"{waitsec}",
        "indices": dict(sorted(index_data.items())),
    }

    # Output the results to stdout
    # print(json.dumps(output_data, indent=4))

    # Output the file
    with open(args.outfile, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=4)
