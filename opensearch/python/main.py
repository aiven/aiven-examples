# Create OpenSearch Python Client
import argparse
import datetime
import json
import time
from random import randint, random
from typing import Dict

from opensearchpy import NotFoundError, OpenSearch


def get_document(
    opensearch: OpenSearch,
    doc_id: int,
    index_name: str,
    doc_name: str,
) -> Dict:
    """Returns OpenSearch document as a dict."""
    try:
        return opensearch.get(index=index_name, doc_type=doc_name, id=doc_id)
    except NotFoundError:
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--url",
        help="OpenSearch URL from Aiven console in the form "
        "https://<user>:<password>@<host>:<port>",
        required=True,
    )
    args = parser.parse_args()

    opensearch = OpenSearch(args.url, use_ssl=True)
    doc_name = str(input("Enter doc type or `to _doc` (default): ") or "_doc")
    index_name = str(
        input("Enter index name or `py_example` (default): ") or "py_example"
    )

    person = {
        "name": "John",
        "height": 185,
        "mass": 77,
        "birth_year": 1980,
        "gender": "male",
        "created": datetime.datetime.now(),
        "edited": datetime.datetime.now(),
    }

    doc_id = randint(1, 5000)

    # Create a document
    opensearch.index(index=index_name, doc_type=doc_name, id=doc_id, body=person)

    start = time.monotonic()

    # Retrieve document
    result = get_document(opensearch, doc_id, index_name, doc_name)
    while not result and time.monotonic() - start < 60:
        time.sleep(1)
        result = get_document(opensearch, doc_id, index_name)

    # Display document
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
