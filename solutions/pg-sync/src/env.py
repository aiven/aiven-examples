import json
from json import JSONDecodeError
import os
import sys
import datetime

from loguru import logger


KAFKA_BROKER = os.environ.get('KAFKA_BROKER', 'localhost:9092')

try:
    config_file = os.environ['CONFIG_FILE']
    with open(config_file, 'r') as f:
        CONFIG = json.load(f)
except KeyError:
    logger.error("set the CDC_TOPIC_NAME environment variable")
    sys.exit(1)
except OSError:
    logger.error("Could not open configuration file")
    sys.exit(1)
except JSONDecodeError:
    logger.error("Could not parse configuration file. Invalid JSON")
    sys.exit(1)

PG_HOST = os.environ.get('PG_HOST', 'localhost')
PG_PORT = os.environ.get('PG_PORT', '5432')
PG_USER = os.environ.get('PG_USER', 'avnadmin')
PG_PW = os.environ.get('PG_PW', '')
PG_DB = os.environ.get('PG_DB', 'defaultdb')
PG_SSL = os.environ.get('PG_SSL', 'require')

EPOCH_DATE = datetime.date(1970, 1, 1)
EPOCH_DATETIME = datetime.datetime(1970, 1, 1, 0, 0, 0)
