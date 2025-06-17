# python populate_indices.py --es_host https://localhost:9200 --es_user admin --es_password admin --indices 'index_noism_1,index_noism_2,index_noism_3,logs1,logs2'

from elasticsearch_client import create_es_client
import argparse
import time
import uuid


# Index the document (empty body, just the _id)
def index_document(index_name):
    # Generate a random unique ID
    doc_id = str(uuid.uuid4())

    es.index(index=index_name, id=doc_id, body={})
    print(f"Indexed document with _id: {doc_id} to index: {index_name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Index documents into the specified Elasticsearch indices"
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
    parser.add_argument(
        "--indices",
        type=str,
        required=True,
        help="comma separated list of indices/alias to populate",
    )
    args = parser.parse_args()

    es = create_es_client(args.es_host, args.es_user, args.es_password)

    indices = args.indices.split(",")
    try:
        print("Starting to write documents. Press Ctrl+C to stop.")
        i = 0
        while True:
            for index_name in indices:
                index_document(index_name)
            if i % 100 == 0:
                es.indices.refresh(index=",".join(indices))
                time.sleep(0.01)
            i += 1
    except KeyboardInterrupt:
        print("\nInterrupted! Stopping document writes.")
