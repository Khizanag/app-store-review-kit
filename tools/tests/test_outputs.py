import json
from pathlib import Path

import pytest

from rulebook import coverage
from rulebook.build import compile_rulebook
from rulebook.cli import main
from rulebook.model import load

from .conftest import VALID_RULE, WriteRule


def test_compiles_rules_and_catalogs(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE)
    payload = json.loads(compile_rulebook(load(repo)))

    assert payload["schema_version"] == 1
    assert payload["guidelines_revision"] == "2026-06-08"
    assert set(payload["catalogs"]) == {"codes", "traits"}
    rule = payload["rules"][0]
    assert rule["automation"] == "automated"
    assert rule["since"] == "2024-05-01"
    assert "review" not in rule


def test_coverage_levels(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE)
    levels = {row.slug: row.level for row in coverage.rows(load(repo))}
    assert levels == {"5.1": "uncovered", "5.1.1": "automated", "2.5.7": "n/a"}
    assert "| [5.1.1 Data](guidelines/5.1.1.md) | automated | `privacy.example` |" in (
        coverage.render(load(repo))
    )


def test_cli_validate_build_and_check(
    repo: Path, write_rule: WriteRule, capsys: pytest.CaptureFixture[str]
) -> None:
    write_rule("privacy/example.toml", VALID_RULE)
    root = ["--root", str(repo)]

    assert main([*root, "validate"]) == 0
    assert main([*root, "build", "--check"]) == 1
    assert main([*root, "build"]) == 0
    assert main([*root, "build", "--check"]) == 0
    assert main([*root, "coverage"]) == 0
    assert (repo / "COVERAGE.md").exists()

    write_rule("privacy/example.toml", VALID_RULE.replace('"error"', '"fatal"'))
    assert main([*root, "validate"]) == 1
    assert "severity 'fatal'" in capsys.readouterr().err
