from env import PG_HOST, PG_DB, PG_SSL, PG_PORT, PG_USER, PG_PW
from psycopg_pool import ConnectionPool

creds = {'host': PG_HOST,
         'port': PG_PORT,
         'user': PG_USER,
         'password': PG_PW,
         'dbname': PG_DB,
         'sslmode': PG_SSL}


def create_db_pool(open: bool = True, **kwargs):
    return ConnectionPool(min_size=3,
                          open=open,
                          kwargs={**creds, **kwargs})
