import os
import sys
import datetime

KAFKA_BROKER = os.environ.get('KAFKA_BROKER', 'localhost:9092')
try:
    CDC_TOPIC_NAME = os.environ['CDC_TOPIC_NAME']
except KeyError:
    print("set the CDC_TOPIC_NAME environment variable")
    sys.exit(1)

DATE_FIELDS = set(_ for _ in (os.environ.get('DATE_FIELDS', '')).split(',') if _)
TIME_FIELDS = set(_ for _ in (os.environ.get('TIME_FIELDS', '')).split(',') if _)
DATETIME_MILLI_FIELDS = set(_ for _ in (os.environ.get('DATETIME_MILLI_FIELDS', '')).split(',') if _)
DATETIME_MICRO_FIELDS = set(_ for _ in (os.environ.get('DATETIME_MICRO_FIELDS', '')).split(',') if _)
TIMESTAMP_FIELDS = set(_ for _ in (os.environ.get('TIMESTAMP_FIELDS', '')).split(',') if _)
SET_FIELDS = set(_ for _ in (os.environ.get('SET_FIELDS', '')).split(',') if _)
BINARY_FIELDS = set(_ for _ in (os.environ.get('BINARY_FIELDS', '')).split(',') if _)
BINARY_ENCODING = os.environ.get('BINARY_ENCODING', 'utf-8')

ROW_IDENTIFIER = set(_ for _ in (os.environ.get('ROW_IDENTIFIER', '')).split(',') if _)

PG_HOST = os.environ.get('PG_HOST', 'localhost')
PG_PORT = os.environ.get('PG_PORT', '5432')
PG_USER = os.environ.get('PG_USER', 'avnadmin')
PG_PW = os.environ.get('PG_PW', '')
PG_DB = os.environ.get('PG_DB', 'defaultdb')
PG_SSL = os.environ.get('PG_SSL', 'require')

EPOCH_TIMESTAMP = datetime.date(1970, 1, 1)
