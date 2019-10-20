#!/usr/bin/env python3
# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import argparse
import datetime

from elasticsearch import Elasticsearch

import json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', help="Elasticsearch URL from Aiven console in the form "
                                      "https://<user>:<password>@<host>:<port>", required=True)
    args = parser.parse_args()

    es = Elasticsearch(args.url, verify_certs=False)

    person = {
        "name": "John",
        "height": 185,
        "mass": 77,
        "birth_year": 1980,
        "gender": "male",
        "created": datetime.datetime.now(),
        "edited": datetime.datetime.now()
    }

    es.index(index="people", doc_type="people", id=1, body=person)
    result = es.get(index='people', doc_type='people', id=1)
    print(json.dumps(result, indent=4, sort_keys=True))


if __name__ == '__main__':
    main()
