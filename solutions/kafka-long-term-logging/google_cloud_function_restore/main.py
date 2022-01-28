from uuid import uuid4
from opensearchpy import OpenSearch
from google.cloud import storage
import json
import os

storage_client = storage.Client()

os_client = OpenSearch(
    hosts = [{'host': os.getenv("OS_HOST"), 'port': os.getenv("OS_PORT")}],
    http_compress = True, # enables gzip compression for request bodies
    http_auth = (os.getenv("OS_USER"), os.getenv("OS_PWD")),
    use_ssl = True,
    verify_certs = False,
    ssl_assert_hostname = False,
    ssl_show_warn = False,
)

def restore_logs(request):
    req = request.get_json()
    bucket = storage_client.get_bucket(req["bucket"])
    blob = bucket.blob(req["file"])
    contents = blob.download_as_string()
    doc = json.loads(contents)
    for d in doc:
        try:
            response = os_client.index(
                index = req["index"],
                body = d,
                id = uuid4(),
                refresh = True
            )
            print(response)
        except Exception as e:
            print(e)
            return {"success": "false", "reason": str(e)}
    return {"success": "true", "result": doc}
