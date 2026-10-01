from __future__ import annotations

from datetime import date
from typing import Any

Catalogs = dict[str, dict[str, Any]]


def trait_names(catalogs: Catalogs) -> set[str]:
    return {trait["id"] for trait in catalogs.get("traits", {}).get("traits", [])}


def validate_catalogs(catalogs: Catalogs, rule_ids: set[str]) -> list[str]:
    return [
        *_validate_traits(catalogs),
        *_validate_profiles(catalogs),
        *_validate_deadlines(catalogs, rule_ids),
    ]


def _validate_traits(catalogs: Catalogs) -> list[str]:
    problems: list[str] = []
    seen: set[str] = set()
    for trait in catalogs.get("traits", {}).get("traits", []):
        name = trait.get("id", "?")
        for key in ("id", "summary"):
            if key not in trait:
                problems.append(f"catalogs/traits.toml: trait '{name}' missing '{key}'")
        if name in seen:
            problems.append(f"catalogs/traits.toml: duplicate trait '{name}'")
        seen.add(name)
    return problems


def _validate_profiles(catalogs: Catalogs) -> list[str]:
    known = trait_names(catalogs)
    problems: list[str] = []
    for profile in catalogs.get("profiles", {}).get("profiles", []):
        name = profile.get("id", "?")
        if "summary" not in profile:
            problems.append(f"catalogs/profiles.toml: profile '{name}' missing 'summary'")
        problems.extend(
            f"catalogs/profiles.toml: profile '{name}' names unknown trait '{trait}'"
            for trait in profile.get("traits", [])
            if trait not in known
        )
    return problems


def _validate_deadlines(catalogs: Catalogs, rule_ids: set[str]) -> list[str]:
    problems: list[str] = []
    for deadline in catalogs.get("deadlines", {}).get("deadlines", []):
        name = deadline.get("id", "?")
        where = f"catalogs/deadlines.toml: deadline '{name}'"
        for key in ("id", "date", "title", "summary", "source"):
            if key not in deadline:
                problems.append(f"{where} missing '{key}'")
        if "date" in deadline and not isinstance(deadline["date"], date):
            problems.append(f"{where} date must be a TOML date")
        if not str(deadline.get("source", "https://")).startswith("https://"):
            problems.append(f"{where} source must be https")
        rule = deadline.get("rule")
        if rule is not None and rule not in rule_ids:
            problems.append(f"{where} names unknown rule '{rule}'")
    return problems
