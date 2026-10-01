from __future__ import annotations

import json
import re
import tomllib
from dataclasses import dataclass, field
from datetime import date
from enum import StrEnum
from pathlib import Path
from typing import Any

from rulebook.catalogs import trait_names, validate_catalogs

RULE_ID = re.compile(r"^[a-z]+(-[a-z]+)*\.[a-z0-9]+(-[a-z0-9]+)*$")
ITMS_CODE = re.compile(r"^ITMS-\d{5}$")
REQUIRED_FIELDS = ("id", "title", "severity", "evidence", "enforced_by", "summary", "fix")
OPTIONAL_FIELDS = (
    "guidelines",
    "applies_when",
    "since",
    "itms",
    "references",
    "check",
    "review",
)


class Severity(StrEnum):
    ERROR = "error"
    WARNING = "warning"
    NOTE = "note"


class Evidence(StrEnum):
    SOURCE = "source"
    PLIST = "plist"
    ENTITLEMENTS = "entitlements"
    MANIFEST = "manifest"
    PROJECT = "project"
    BINARY = "binary"
    METADATA = "metadata"
    RUNTIME = "runtime"
    HUMAN = "human"


class Enforcement(StrEnum):
    UPLOAD = "upload"
    APP_STORE_CONNECT = "app-store-connect"
    APP_REVIEW = "app-review"


class Confidence(StrEnum):
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"


class Automation(StrEnum):
    AUTOMATED = "automated"
    ASSISTED = "assisted"
    MANUAL = "manual"


@dataclass(frozen=True)
class Rule:
    id: str
    title: str
    severity: Severity
    evidence: tuple[Evidence, ...]
    enforced_by: Enforcement
    summary: str
    fix: str
    guidelines: tuple[str, ...] = ()
    applies_when: tuple[str, ...] = ()
    since: str | None = None
    itms: tuple[str, ...] = ()
    references: tuple[str, ...] = ()
    check: dict[str, Any] | None = None
    review: tuple[str, ...] = ()
    path: Path = field(default=Path(), compare=False)

    @property
    def automation(self) -> Automation:
        if self.check is None:
            return Automation.MANUAL
        return Automation.ASSISTED if self.review else Automation.AUTOMATED

    def to_json(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "id": self.id,
            "title": self.title,
            "severity": self.severity.value,
            "evidence": [item.value for item in self.evidence],
            "enforced_by": self.enforced_by.value,
            "automation": self.automation.value,
            "guidelines": list(self.guidelines),
            "applies_when": list(self.applies_when),
            "summary": self.summary,
            "fix": self.fix,
        }
        optional: dict[str, Any] = {
            "since": self.since,
            "itms": list(self.itms),
            "references": list(self.references),
            "check": self.check,
            "review": list(self.review),
        }
        payload.update({key: value for key, value in optional.items() if value})
        return payload


@dataclass(frozen=True)
class Rulebook:
    rules: tuple[Rule, ...]
    catalogs: dict[str, dict[str, Any]]
    guidelines_revision: str
    guideline_sections: dict[str, dict[str, Any]]


class RulebookError(Exception):
    def __init__(self, problems: list[str]) -> None:
        super().__init__("\n".join(problems))
        self.problems = problems


def load(root: Path) -> Rulebook:
    index = json.loads((root / "guidelines" / "index.json").read_text())
    sections = {section["slug"]: section for section in index["sections"]}
    catalogs = {path.stem: _read_toml(path) for path in sorted((root / "catalogs").glob("*.toml"))}

    problems: list[str] = []
    rules: list[Rule] = []
    for path in sorted((root / "rules").rglob("*.toml")):
        rule, rule_problems = _parse_rule(path, root, sections, catalogs)
        problems.extend(rule_problems)
        if rule is not None:
            rules.append(rule)

    problems.extend(validate_catalogs(catalogs, {rule.id for rule in rules}))
    if problems:
        raise RulebookError(problems)
    return Rulebook(tuple(rules), catalogs, index["last_updated"], sections)


def _read_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as file:
        return tomllib.load(file)


def _parse_rule(
    path: Path,
    root: Path,
    sections: dict[str, dict[str, Any]],
    catalogs: dict[str, dict[str, Any]],
) -> tuple[Rule | None, list[str]]:
    where = path.relative_to(root)
    try:
        data = _read_toml(path)
    except tomllib.TOMLDecodeError as error:
        return None, [f"{where}: invalid TOML: {error}"]

    problems = [f"{where}: missing '{key}'" for key in REQUIRED_FIELDS if key not in data]
    unknown = set(data) - set(REQUIRED_FIELDS) - set(OPTIONAL_FIELDS)
    problems.extend(f"{where}: unknown field '{key}'" for key in sorted(unknown))
    if problems:
        return None, problems

    expected_id = f"{path.parent.name}.{path.stem}"
    if data["id"] != expected_id:
        problems.append(f"{where}: id '{data['id']}' must be '{expected_id}' to match its path")
    if not RULE_ID.match(data["id"]):
        problems.append(f"{where}: id '{data['id']}' is not '<area>.<kebab-name>'")

    severity = _enum(Severity, data["severity"], "severity", where, problems)
    enforced_by = _enum(Enforcement, data["enforced_by"], "enforced_by", where, problems)
    evidence = tuple(
        item
        for raw in data["evidence"]
        if (item := _enum(Evidence, raw, "evidence", where, problems)) is not None
    )
    if not evidence:
        problems.append(f"{where}: evidence must list at least one kind")

    guidelines = tuple(data.get("guidelines", ()))
    problems.extend(
        f"{where}: unknown guideline section '{g}'" for g in guidelines if g not in sections
    )
    if enforced_by is Enforcement.APP_REVIEW and not guidelines:
        problems.append(f"{where}: app-review rules must cite at least one guideline")

    applies_when = tuple(data.get("applies_when", ()))
    known_traits = trait_names(catalogs)
    problems.extend(
        f"{where}: unknown trait '{trait}' in applies_when"
        for trait in applies_when
        if trait not in known_traits
    )

    itms = tuple(data.get("itms", ()))
    problems.extend(
        f"{where}: bad ITMS code '{code}'" for code in itms if not ITMS_CODE.match(code)
    )

    references = tuple(data.get("references", ()))
    problems.extend(
        f"{where}: reference must be https: '{url}'"
        for url in references
        if not url.startswith("https://")
    )

    since = data.get("since")
    if since is not None:
        since = str(since)
        try:
            date.fromisoformat(since)
        except ValueError:
            problems.append(f"{where}: since '{since}' is not an ISO date")

    check = data.get("check")
    review = tuple(data.get("review", {}).get("questions", ()))
    if check is None and not review:
        problems.append(f"{where}: needs a [check], [review] questions, or both")
    if check is not None:
        if "id" not in check:
            problems.append(f"{where}: [check] needs an 'id' naming the engine check")
        if "confidence" not in check:
            problems.append(f"{where}: [check] needs a 'confidence' of high, medium, or low")
        else:
            _enum(Confidence, check["confidence"], "confidence", where, problems)
        catalog = check.get("catalog")
        if catalog is not None and catalog not in catalogs:
            problems.append(f"{where}: [check] names unknown catalog '{catalog}'")

    if problems or severity is None or enforced_by is None:
        return None, problems

    return (
        Rule(
            id=data["id"],
            title=data["title"],
            severity=severity,
            evidence=evidence,
            enforced_by=enforced_by,
            summary=data["summary"].strip(),
            fix=data["fix"].strip(),
            guidelines=guidelines,
            applies_when=applies_when,
            since=since,
            itms=itms,
            references=references,
            check=check,
            review=review,
            path=where,
        ),
        [],
    )


def _enum[E: StrEnum](
    kind: type[E],
    raw: object,
    name: str,
    where: Path,
    problems: list[str],
) -> E | None:
    try:
        return kind(str(raw))
    except ValueError:
        allowed = ", ".join(item.value for item in kind)
        problems.append(f"{where}: {name} '{raw}' is not one of: {allowed}")
        return None
