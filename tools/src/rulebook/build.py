from __future__ import annotations

import json
from typing import Any

from rulebook.model import Rulebook

SCHEMA_VERSION = 1


def compile_rulebook(rulebook: Rulebook) -> str:
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "guidelines_revision": rulebook.guidelines_revision,
        "rules": [rule.to_json() for rule in sorted(rulebook.rules, key=lambda r: r.id)],
        "catalogs": rulebook.catalogs,
    }
    return json.dumps(payload, indent=2, ensure_ascii=False, default=str) + "\n"
