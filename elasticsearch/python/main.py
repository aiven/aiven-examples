#!/usr/bin/env python3
# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import argparse
import datetime
import time
from random import random, randint

from elasticsearch import Elasticsearch, NotFoundError

import json

INDEX = 'python_example'
DOC_TYPE = 'people'


def get_document(elastic, doc_id):
    try:
        return elastic.get(index=INDEX, doc_type=DOC_TYPE, id=doc_id)
    except NotFoundError:
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', help="Elasticsearch URL from Aiven console in the form "
                                      "https://<user>:<password>@<host>:<port>", required=True)
    args = parser.parse_args()

    elastic = Elasticsearch(args.url, verify_certs=False)

    person = {
        "name": "John",
        "height": 185,
        "mass": 77,
        "birth_year": 1980,
        "gender": "male",
        "created": datetime.datetime.now(),
        "edited": datetime.datetime.now()
    }

    doc_id = randint(1, 5000)
    # Create a document
    elastic.index(index=INDEX, doc_type=DOC_TYPE, id=doc_id, body=person)

    start = time.monotonic()

    # Retrieve document
    result = get_document(elastic, doc_id)
    while not result and time.monotonic() - start < 60:
        time.sleep(1)
        result = get_document(elastic, doc_id)

    # Display document
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
