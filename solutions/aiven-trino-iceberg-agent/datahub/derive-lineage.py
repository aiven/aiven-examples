#!/usr/bin/env python3
"""Derive Kafka-topic -> Iceberg-table lineage from Kafka Connect itself and
emit it to DataHub. No dataset names are hardcoded: the script asks the
Connect REST API for every connector, and for each Apache Iceberg sink
(`org.apache.iceberg.connect.IcebergSinkConnector`) reads `topics` and
`iceberg.tables` from its live config — the same source of truth DataHub's
kafka-connect ingestion uses for the connector classes it recognizes. This
fills that source's gap for the Iceberg sink, and scales to any number of
connectors unchanged.

Setup:
    python3.13 -m venv venv && ./venv/bin/pip install acryl-datahub requests

Env:
    CONNECT_URL      https://<connect-host>:443   (Aiven: the public- host)
    CONNECT_USER     avnadmin
    CONNECT_PASSWORD <connect service password>
    DATAHUB_GMS_URL  https://<gms-host>  or  https://<frontend-host>/api/gms
    DATAHUB_TOKEN    <personal access token>      (optional if auth is off)

Run:
    ./venv/bin/python derive-lineage.py [--dry-run]

Notes:
  - A sink with multiple topics and multiple tables fans out every record to
    every listed table, so topic->table edges are emitted for each pair.
  - Sinks using dynamic routing (`iceberg.tables.dynamic-enabled` +
    `iceberg.tables.route-field`) name tables per-record; static config can't
    resolve those, so they are reported and skipped.
  - Existing upstreams on each table are preserved (read-modify-write).
"""
import os
import sys

import requests
from datahub.emitter.mce_builder import make_dataset_urn
from datahub.emitter.mcp import MetadataChangeProposalWrapper
from datahub.ingestion.graph.client import DatahubClientConfig, DataHubGraph
from datahub.metadata.schema_classes import (
    DatasetLineageTypeClass,
    UpstreamClass,
    UpstreamLineageClass,
)

ICEBERG_SINK_CLASS = "org.apache.iceberg.connect.IcebergSinkConnector"


def env(key, default=None, required=False):
    v = os.environ.get(key, default)
    if required and not v:
        sys.exit(f"Set {key}")
    return v


def main():
    dry_run = "--dry-run" in sys.argv
    connect_url = env("CONNECT_URL", required=True).rstrip("/")
    auth = (env("CONNECT_USER", "avnadmin"), env("CONNECT_PASSWORD", required=True))
    gms = env("DATAHUB_GMS_URL", required=True)
    token = env("DATAHUB_TOKEN")

    names = requests.get(f"{connect_url}/connectors", auth=auth, timeout=30)
    names.raise_for_status()

    edges = []  # (connector, topic, table)
    for name in names.json():
        cfg = requests.get(
            f"{connect_url}/connectors/{name}/config", auth=auth, timeout=30
        )
        cfg.raise_for_status()
        cfg = cfg.json()
        if cfg.get("connector.class") != ICEBERG_SINK_CLASS:
            continue
        if cfg.get("iceberg.tables.dynamic-enabled", "false").lower() == "true":
            print(f"SKIP {name}: dynamic table routing "
                  f"(route field {cfg.get('iceberg.tables.route-field')!r}) — "
                  "table names are per-record, not derivable from config")
            continue
        topics = [t.strip() for t in cfg.get("topics", "").split(",") if t.strip()]
        tables = [t.strip() for t in cfg.get("iceberg.tables", "").split(",") if t.strip()]
        if not topics or not tables:
            print(f"SKIP {name}: no static topics/tables in config")
            continue
        for topic in topics:
            for table in tables:
                edges.append((name, topic, table))

    if not edges:
        print("No Iceberg sink lineage derivable from Connect configs.")
        return

    # Group by destination table: one upstreamLineage aspect per table.
    by_table = {}
    for name, topic, table in edges:
        by_table.setdefault(table, []).append((name, topic))

    graph = None
    if not dry_run:
        graph = DataHubGraph(DatahubClientConfig(server=gms, token=token))

    for table, sources in by_table.items():
        table_urn = make_dataset_urn(platform="iceberg", name=table, env="PROD")
        topic_urns = {
            make_dataset_urn(platform="kafka", name=topic, env="PROD")
            for _, topic in sources
        }
        for name, topic in sources:
            print(f"{name}: kafka:{topic} -> iceberg:{table}")
        if dry_run:
            continue
        existing = graph.get_aspect(table_urn, UpstreamLineageClass)
        upstreams = list(existing.upstreams) if existing else []
        known = {u.dataset for u in upstreams}
        upstreams += [
            UpstreamClass(dataset=u, type=DatasetLineageTypeClass.TRANSFORMED)
            for u in sorted(topic_urns - known)
        ]
        graph.emit_mcp(
            MetadataChangeProposalWrapper(
                entityUrn=table_urn, aspect=UpstreamLineageClass(upstreams=upstreams)
            )
        )
        print(f"  emitted upstreamLineage for {table_urn} ({len(upstreams)} upstream(s))")

    print("Done." if not dry_run else "Dry run — nothing emitted.")


if __name__ == "__main__":
    main()
