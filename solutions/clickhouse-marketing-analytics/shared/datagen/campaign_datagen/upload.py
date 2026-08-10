"""Upload generated month directories to GCS.

Auth: Application Default Credentials (`gcloud auth application-default login`).
Skips files whose size+sha match the remote (safe re-runs); uploads part files
first and each month's _manifest.json last, so a manifest never references a
part that isn't there yet.
"""

from __future__ import annotations

import base64
import hashlib
from pathlib import Path


def upload(root: Path, bucket_name: str, prefix: str, months: list[str] | None = None) -> None:
    from google.cloud import storage  # deferred so generate/validate work without it

    client = storage.Client()
    bucket = client.bucket(bucket_name)

    month_dirs = sorted(d for d in root.glob("month=*") if d.is_dir())
    if months:
        month_dirs = [d for d in month_dirs if d.name.split("=", 1)[1] in months]
    if not month_dirs:
        raise SystemExit(f"nothing to upload under {root}")

    def put(path: Path) -> None:
        blob_name = f"{prefix}/{path.relative_to(root)}"
        blob = bucket.blob(blob_name)
        md5 = base64.b64encode(hashlib.md5(path.read_bytes()).digest()).decode()
        blob.reload() if blob.exists() else None
        if blob.exists() and blob.md5_hash == md5:
            print(f"  = gs://{bucket_name}/{blob_name} (unchanged)")
            return
        blob.upload_from_filename(path, if_generation_match=None)
        print(f"  ^ gs://{bucket_name}/{blob_name} ({path.stat().st_size / 1e6:.1f} MB)")

    for d in month_dirs:
        print(f"month {d.name}:")
        for p in sorted(d.glob("part-*.parquet")):
            put(p)
        manifest = d / "_manifest.json"
        if manifest.exists():
            put(manifest)
    if (root / "_manifest.json").exists():
        put(root / "_manifest.json")

    print("\nLoad into ClickHouse (whole dataset):")
    print(f"""  INSERT INTO campaign_events
  SELECT * FROM s3('https://storage.googleapis.com/{bucket_name}/{prefix}/month=*/part-*.parquet', NOSIGN, 'Parquet')
  SETTINGS max_insert_threads = 4, async_insert = 0;""")
