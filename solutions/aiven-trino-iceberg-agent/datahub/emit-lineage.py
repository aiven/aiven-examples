#!/usr/bin/env python3
"""Emit the one lineage edge DataHub cannot infer:

    kafka:live_orders.public.orders  ──►  iceberg:ecommerce.live_orders

DataHub's kafka-connect ingestion doesn't recognize the Apache Iceberg sink
connector class, so this edge never appears automatically. Run this once after
(re)building the DataHub instance; ingestion re-runs do not remove it.

Setup:
    python3 -m venv venv && ./venv/bin/pip install acryl-datahub
    export DATAHUB_GMS_URL="https://<datahub-frontend-host>/api/gms"
    export DATAHUB_TOKEN="<personal access token>"   # UI -> Settings -> Access Tokens

Run:
    ./venv/bin/python emit-lineage.py

Optional env overrides (defaults match this demo's recipes):
    LINEAGE_TOPIC=live_orders.public.orders
    LINEAGE_TABLE=ecommerce.live_orders

Note: this writes the table's upstreamLineage aspect wholesale. For this demo
the Iceberg table has no other upstreams, so a plain replace is safe; if you
later add more upstreams, switch to DataHubGraph + a read-modify-write.
"""
import os
import sys

from datahub.emitter.mce_builder import make_dataset_urn
from datahub.emitter.mcp import MetadataChangeProposalWrapper
from datahub.emitter.rest_emitter import DatahubRestEmitter
from datahub.metadata.schema_classes import (
    DatasetLineageTypeClass,
    UpstreamClass,
    UpstreamLineageClass,
)

gms = os.environ.get("DATAHUB_GMS_URL")
if not gms:
    sys.exit("Set DATAHUB_GMS_URL (e.g. https://<frontend-host>/api/gms)")
token = os.environ.get("DATAHUB_TOKEN")  # optional if GMS auth is off

topic_urn = make_dataset_urn(
    platform="kafka",
    name=os.environ.get("LINEAGE_TOPIC", "live_orders.public.orders"),
    env="PROD",
)
table_urn = make_dataset_urn(
    platform="iceberg",
    name=os.environ.get("LINEAGE_TABLE", "ecommerce.live_orders"),
    env="PROD",
)

mcp = MetadataChangeProposalWrapper(
    entityUrn=table_urn,
    aspect=UpstreamLineageClass(
        upstreams=[
            UpstreamClass(dataset=topic_urn, type=DatasetLineageTypeClass.TRANSFORMED)
        ]
    ),
)

emitter = DatahubRestEmitter(gms_server=gms, token=token)
emitter.test_connection()
emitter.emit_mcp(mcp)
print(f"Emitted lineage:\n  upstream : {topic_urn}\n  downstream: {table_urn}")
