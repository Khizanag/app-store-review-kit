from datetime import date

from rulebook.catalogs import Catalogs, trait_names, validate_catalogs


def test_valid_catalogs_pass() -> None:
    catalogs: Catalogs = {
        "traits": {"traits": [{"id": "accounts", "summary": "Accounts."}]},
        "profiles": {"profiles": [{"id": "app", "summary": "App.", "traits": ["accounts"]}]},
        "deadlines": {
            "deadlines": [
                {
                    "id": "sdk",
                    "date": date(2026, 4, 28),
                    "title": "SDK",
                    "summary": "Build with the new SDK.",
                    "source": "https://developer.apple.com/news/",
                    "rule": "build.sdk-minimum",
                }
            ]
        },
    }
    assert trait_names(catalogs) == {"accounts"}
    assert validate_catalogs(catalogs, {"build.sdk-minimum"}) == []


def test_reports_catalog_problems() -> None:
    catalogs: Catalogs = {
        "traits": {"traits": [{"id": "accounts"}, {"id": "accounts", "summary": "Again."}]},
        "profiles": {"profiles": [{"id": "app", "traits": ["pets"]}]},
        "deadlines": {
            "deadlines": [
                {"id": "sdk", "date": "soon", "source": "http://x", "rule": "build.nope"},
            ]
        },
    }
    assert validate_catalogs(catalogs, set()) == [
        "catalogs/traits.toml: trait 'accounts' missing 'summary'",
        "catalogs/traits.toml: duplicate trait 'accounts'",
        "catalogs/profiles.toml: profile 'app' missing 'summary'",
        "catalogs/profiles.toml: profile 'app' names unknown trait 'pets'",
        "catalogs/deadlines.toml: deadline 'sdk' missing 'title'",
        "catalogs/deadlines.toml: deadline 'sdk' missing 'summary'",
        "catalogs/deadlines.toml: deadline 'sdk' date must be a TOML date",
        "catalogs/deadlines.toml: deadline 'sdk' source must be https",
        "catalogs/deadlines.toml: deadline 'sdk' names unknown rule 'build.nope'",
    ]
