from pathlib import Path

import pytest

from rulebook.model import Automation, RulebookError, Severity, load

from .conftest import VALID_RULE, WriteRule


def problems(repo: Path) -> list[str]:
    with pytest.raises(RulebookError) as raised:
        load(repo)
    return raised.value.problems


def test_loads_valid_rule(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE)
    rulebook = load(repo)

    rule = rulebook.rules[0]
    assert rule.severity is Severity.ERROR
    assert rule.since == "2024-05-01"
    assert rule.automation is Automation.AUTOMATED
    assert rulebook.guidelines_revision == "2026-06-08"
    assert rulebook.catalogs["codes"] == {"codes": ["CA92.1"]}


def test_automation_reflects_check_and_review(repo: Path, write_rule: WriteRule) -> None:
    assisted = VALID_RULE + '\n[review]\nquestions = ["Is it so?"]\n'
    write_rule("privacy/example.toml", assisted)
    manual = VALID_RULE.replace('id = "privacy.example"', 'id = "privacy.manual"').split("[check]")[
        0
    ]
    write_rule("privacy/manual.toml", manual + '[review]\nquestions = ["Is it so?"]\n')

    automation = {rule.id: rule.automation for rule in load(repo).rules}
    assert automation == {
        "privacy.example": Automation.ASSISTED,
        "privacy.manual": Automation.MANUAL,
    }


def test_id_must_match_path(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/other.toml", VALID_RULE)
    assert problems(repo) == [
        "rules/privacy/other.toml: id 'privacy.example' must be 'privacy.other' to match its path"
    ]


def test_reports_every_bad_field(repo: Path, write_rule: WriteRule) -> None:
    bad = (
        VALID_RULE.replace('"error"', '"fatal"')
        .replace('["manifest"]', '["manifest", "vibes"]')
        .replace('["5.1.1"]', '["9.9"]')
        .replace('catalog = "codes"', 'catalog = "missing"')
        .replace("2024-05-01", '"May 2024"')
        .replace(
            "[check]",
            'itms = ["91053"]\nreferences = ["http://example.com"]\n[check]',
        )
    )
    write_rule("privacy/example.toml", bad)
    found = problems(repo)
    for fragment in (
        "severity 'fatal'",
        "evidence 'vibes'",
        "unknown guideline section '9.9'",
        "unknown catalog 'missing'",
        "not an ISO date",
        "bad ITMS code '91053'",
        "reference must be https",
    ):
        assert any(fragment in p for p in found), fragment


def test_unknown_field_stops_validation(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE.replace("[check]", "extra = 1\n[check]"))
    assert problems(repo) == ["rules/privacy/example.toml: unknown field 'extra'"]


def test_fields_after_a_table_belong_to_it(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE + 'itms = ["91053"]\n')
    assert load(repo).rules[0].check == {"id": "example", "catalog": "codes", "itms": ["91053"]}


def test_requires_check_or_review(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE.split("[check]")[0])
    assert problems(repo) == [
        "rules/privacy/example.toml: needs a [check], [review] questions, or both"
    ]


def test_app_review_rules_cite_a_guideline(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE.replace('guidelines = ["5.1.1"]\n', ""))
    assert problems(repo) == [
        "rules/privacy/example.toml: app-review rules must cite at least one guideline"
    ]


def test_reports_missing_fields_and_bad_toml(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/empty.toml", 'id = "privacy.empty"\n')
    write_rule("privacy/broken.toml", "id = ")
    found = problems(repo)
    assert "rules/privacy/empty.toml: missing 'title'" in found
    assert any(p.startswith("rules/privacy/broken.toml: invalid TOML") for p in found)


def test_check_needs_engine_id(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE.replace('id = "example"\n', ""))
    assert problems(repo) == [
        "rules/privacy/example.toml: [check] needs an 'id' naming the engine check"
    ]


def test_rejects_badly_shaped_id(repo: Path, write_rule: WriteRule) -> None:
    write_rule("Odd_Area/Bad_Name.toml", VALID_RULE.replace("privacy.example", "Odd_Area.Bad_Name"))
    assert problems(repo) == [
        "rules/Odd_Area/Bad_Name.toml: id 'Odd_Area.Bad_Name' is not '<area>.<kebab-name>'"
    ]


def test_evidence_cannot_be_empty(repo: Path, write_rule: WriteRule) -> None:
    write_rule("privacy/example.toml", VALID_RULE.replace('["manifest"]', "[]"))
    assert problems(repo) == ["rules/privacy/example.toml: evidence must list at least one kind"]
