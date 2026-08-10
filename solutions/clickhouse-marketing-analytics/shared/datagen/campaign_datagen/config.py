"""YAML config → attribute-accessible namespace."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import yaml


def _to_ns(obj):
    if isinstance(obj, dict):
        return SimpleNamespace(**{k: _to_ns(v) for k, v in obj.items()})
    if isinstance(obj, list):
        return [_to_ns(v) for v in obj]
    return obj


def load_config(path: str | Path) -> SimpleNamespace:
    with open(path) as f:
        raw = yaml.safe_load(f)
    return _to_ns(raw)
