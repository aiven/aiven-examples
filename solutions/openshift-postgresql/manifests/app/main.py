import os

import psycopg
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="OpenShift + Aiven PostgreSQL demo")

# The Aiven Operator writes connection details into a Kubernetes Secret.
# The Deployment mounts those Secret keys as environment variables.
DATABASE_URL = os.environ["DATABASE_URL"]


def get_connection():
    return psycopg2.connect(DATABASE_URL)


def ensure_table():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS items (
                    id   SERIAL PRIMARY KEY,
                    name TEXT NOT NULL
                )
                """
            )
        conn.commit()


ensure_table()


class Item(BaseModel):
    name: str


@app.get("/healthz")
def health():
    return {"status": "ok"}


@app.get("/items")
def list_items():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name FROM items ORDER BY id")
            rows = cur.fetchall()
    return [{"id": row[0], "name": row[1]} for row in rows]


@app.post("/items", status_code=201)
def create_item(item: Item):
    if not item.name.strip():
        raise HTTPException(status_code=400, detail="name must not be empty")
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO items (name) VALUES (%s) RETURNING id",
                (item.name.strip(),),
            )
            new_id = cur.fetchone()[0]
        conn.commit()
    return {"id": new_id, "name": item.name.strip()}
