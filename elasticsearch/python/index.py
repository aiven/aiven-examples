# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from elasticsearch import Elasticsearch

import json

service_uri = "https://avnadmin:nr0dfnswz36xs9pi@es-3b8d4ed6-myfirstcloudhub.aivencloud.com:15193"
es = Elasticsearch(service_uri, verify_certs=True)

person = {
    "name": "John",
    "height": 185,
    "mass": 77,
    "birth_year": 1980,
    "gender": "male",
    "created": "2018-12-09T13:50:51.644000Z",
    "edited": "2017-12-20T21:17:56.891000Z"
}

es.index(index="people", doc_type="people", id=1, body=person)
result = es.get(index='people', doc_type='people', id=1)
print(json.dumps(result, indent=4, sort_keys=True))
