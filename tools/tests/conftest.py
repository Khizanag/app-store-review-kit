import json
from collections.abc import Callable
from pathlib import Path

import pytest

INDEX = {
    "source": "https://developer.apple.com/app-store/review/guidelines/",
    "last_updated": "2026-06-08",
    "sections": [
        {"slug": "5", "number": "5", "title": "Legal", "parent": None, "omitted": False},
        {"slug": "5.1", "number": "5.1", "title": "Privacy", "parent": "5", "omitted": False},
        {"slug": "5.1.1", "number": "5.1.1", "title": "Data", "parent": "5.1", "omitted": False},
        {"slug": "2.5.7", "number": "2.5.7", "title": "", "parent": "2.5", "omitted": True},
    ],
}

VALID_RULE = """
id = "privacy.example"
title = "Example"
severity = "error"
evidence = ["manifest"]
enforced_by = "app-review"
guidelines = ["5.1.1"]
since = 2024-05-01
summary = "Summary."
fix = "Fix."

[check]
id = "example"
catalog = "codes"
"""

WriteRule = Callable[[str, str], Path]


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    (tmp_path / "guidelines").mkdir()
    (tmp_path / "guidelines" / "index.json").write_text(json.dumps(INDEX))
    (tmp_path / "catalogs").mkdir()
    (tmp_path / "catalogs" / "codes.toml").write_text('codes = ["CA92.1"]\n')
    (tmp_path / "rules" / "privacy").mkdir(parents=True)
    return tmp_path


@pytest.fixture
def write_rule(repo: Path) -> WriteRule:
    def write(relative: str, content: str) -> Path:
        path = repo / "rules" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    return write
