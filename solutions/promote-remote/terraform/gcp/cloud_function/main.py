import requests
from requests.structures import CaseInsensitiveDict

def promote_remote(request):
    """Responds to any HTTP request.
    Args:
        request (flask.Request): HTTP request object.
    Returns:
        The response text or any set of values that can be turned into a
        Response object using
        `make_response <http://flask.pocoo.org/docs/1.0/api/#flask.Flask.make_response>`.
    """
    request_json = request.get_json()

    PROJ = request_json["PROJ"]
    INT_ID = request_json['INTEGRATION_ID']
    TOKEN = request_json['AVN_TOKEN']
    
    headers = CaseInsensitiveDict()
    headers["Accept"] = "application/json"
    headers["Authorization"] = "aivenV1 {}".format(TOKEN)

    AVN_URL = "https://api.aiven.io/v1/project/{}/integration/{}".format(PROJ, INT_ID)

    resp = requests.delete(AVN_URL, headers=headers)
    return resp.json()
