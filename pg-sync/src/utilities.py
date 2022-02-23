import datetime
from ssl import SSLContext
from typing import Dict, List, Optional, Iterable

from aiokafka.helpers import create_ssl_context
from kafka import KafkaConsumer
from pypika import Table, Query, Parameter, Criterion

from env import DATE_FIELDS, TIME_FIELDS, DATETIME_MILLI_FIELDS, DATETIME_MICRO_FIELDS, TIMESTAMP_FIELDS, \
    BINARY_FIELDS, SET_FIELDS, EPOCH_TIMESTAMP, BINARY_ENCODING, ROW_IDENTIFIER


def create_consumer(topic: str, bootstrap_servers: List[str], ssl_context: Optional[SSLContext],
                    **kwargs) -> KafkaConsumer:
    consumer = KafkaConsumer(topic,
                             bootstrap_servers=bootstrap_servers,
                             security_protocol="SSL",
                             ssl_context=ssl_context,
                             **kwargs)
    return consumer


def int_to_date(days_since_epoch: int) -> datetime.date:
    return EPOCH_TIMESTAMP + datetime.timedelta(days=days_since_epoch)


def micro_time(microseconds: int) -> datetime.time:
    hour_conv = (3600 * 1000 * 1000)
    min_conv = (60 * 1000 * 1000)
    sec_conv = (1000 * 1000)

    hours = microseconds // hour_conv
    microseconds -= hours * hour_conv

    minutes = microseconds // min_conv
    microseconds -= minutes * min_conv

    seconds = microseconds // sec_conv
    microseconds -= microseconds * sec_conv

    if microseconds < 0:
        microseconds = 0

    return datetime.time(hour=hours, minute=minutes, second=seconds, microsecond=microseconds)


def milli_to_datetime(milliseconds: int) -> datetime.datetime:
    return EPOCH_TIMESTAMP + datetime.timedelta(microseconds=milliseconds * 1000)


def micro_to_datetime(microseconds: int) -> datetime.datetime:
    return EPOCH_TIMESTAMP + datetime.timedelta(microseconds=microseconds)


def timestamp_str_to_obj(date_str: str) -> datetime.datetime:
    try:
        return datetime.datetime.strptime(date_str, '%Y-%m-%dT%H:%M:%SZ')
    except Exception as e:
        return datetime.datetime.strptime(date_str, '%Y-%m-%dT%H:%M:%S.%fZ')


def binary_value(s: str) -> bytes:
    return s.encode(encoding=BINARY_ENCODING)


def str_to_set_type(s: Optional[str]) -> Optional[List[str]]:
    if s is None:
        return None
    return s.split(',')


def cast_values(keys: Iterable[str], values: Iterable) -> List:
    cast_vals = []
    for k, v in zip(keys, values):
        if k in DATE_FIELDS:
            cast_vals.append(int_to_date(v))
        elif k in TIME_FIELDS:
            cast_vals.append(micro_time(v))
        elif k in DATETIME_MILLI_FIELDS:
            cast_vals.append(milli_to_datetime(v))
        elif k in DATETIME_MICRO_FIELDS:
            cast_vals.append(micro_to_datetime(v))
        elif k in TIMESTAMP_FIELDS:
            cast_vals.append(timestamp_str_to_obj(v))
        elif k in BINARY_FIELDS:
            cast_vals.append(binary_value(v))
        elif k in SET_FIELDS:
            cast_vals.append(str_to_set_type(v))
        else:
            cast_vals.append(v)
    return cast_vals


def make_ssl_context(cafile_path: str, certfile_path: str, keyfile_path: str) -> SSLContext:
    return create_ssl_context(
        cafile=cafile_path,
        certfile=certfile_path,
        keyfile=keyfile_path
    )


def create_update_statement(table_name: str, before: Dict, after: Dict) -> str:
    table = Table(table_name)
    q = Query.update(table)
    keys = ROW_IDENTIFIER if ROW_IDENTIFIER else before.keys()
    for i, k in enumerate(after.keys(), start=1):
        q = q.set(k, Parameter('%s'))
    for i, k in enumerate(keys, start=len(before) + 1):
        q = q.where(table.__getattr__(k) == Parameter('%s'))
    return q.get_sql()


def create_insert_statement(table_name: str, after: Dict) -> str:
    keys, values = after.keys(), after.values()
    table = Table(table_name)
    q = Query.into(table).columns(*keys).insert(*[Parameter('%s') for _ in range(1, len(values) + 1)])
    return q.get_sql()


def create_delete_statement(table_name: str, before: Dict) -> str:
    table = Table(table_name)
    q = Query.from_(table)
    keys = ROW_IDENTIFIER if ROW_IDENTIFIER else before.keys()
    for i, k in enumerate(keys, start=1):
        q = q.where(table.__getattr__(k) == Parameter('%s'))
    return q.delete().get_sql()

