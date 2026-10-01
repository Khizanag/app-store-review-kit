import json
from pathlib import Path

import pytest

from rulebook import mirror

FIXTURE = Path(__file__).parent / "fixtures" / "guidelines.html"


@pytest.fixture
def snapshot() -> mirror.Snapshot:
    return mirror.parse(FIXTURE.read_text())


def by_slug(snapshot: mirror.Snapshot) -> dict[str, mirror.Section]:
    return {section.slug: section for section in snapshot.sections}


def test_reads_last_updated_date(snapshot: mirror.Snapshot) -> None:
    assert snapshot.last_updated == "2026-06-08"


def test_finds_span_and_list_item_anchors(snapshot: mirror.Snapshot) -> None:
    assert [s.slug for s in snapshot.sections] == [
        "introduction",
        "1",
        "1.1",
        "1.1.1",
        "1.1.2",
        "4.2.7",
        "after-you-submit",
    ]


def test_links_parents_and_children(snapshot: mirror.Snapshot) -> None:
    sections = by_slug(snapshot)
    assert sections["1"].children == ("1.1", "4.2.7")
    assert sections["1.1"].children == ("1.1.1", "1.1.2")
    assert sections["1.1.2"].parent == "1.1"
    assert sections["1.1"].parent == "1"


def test_flags_notarization_review(snapshot: mirror.Snapshot) -> None:
    sections = by_slug(snapshot)
    assert sections["1.1.2"].notarization
    assert not sections["1.1.1"].notarization


def test_titles_drop_numbers_and_colons(snapshot: mirror.Snapshot) -> None:
    sections = by_slug(snapshot)
    assert sections["1"].title == "Safety"
    assert sections["1.1"].title == "Objectionable Content"
    assert sections["1.1.1"].title == ""
    assert sections["4.2.7"].title == "Remote Desktop Clients"


def test_body_excludes_nested_sections(snapshot: mirror.Snapshot) -> None:
    sections = by_slug(snapshot)
    assert sections["1"].body == "Be safe."
    assert sections["1.1"].body == "Examples include:"


def test_body_renders_markdown(snapshot: mirror.Snapshot) -> None:
    sections = by_slug(snapshot)
    assert sections["1.1.2"].body == (
        "Violence. See [1.1](1.1.md) and [the terms](https://developer.apple.com/support/terms/)."
    )
    assert (
        sections["4.2.7"].body
        == "Mirror rules.\n\n- Same network.\n- **(ii) Host:** Owned by user."
    )
    assert sections["introduction"].body == "Apps are *great*.\n\n**Developer Documentation**"
    assert sections["after-you-submit"].body.startswith("Wait.\\\nThen check.")


def test_write_emits_files_and_index(snapshot: mirror.Snapshot, tmp_path: Path) -> None:
    (tmp_path / "9.9.md").write_text("stale")
    mirror.write(snapshot, tmp_path)

    assert not (tmp_path / "9.9.md").exists()
    assert "\n## Developer Documentation\n" in (tmp_path / "introduction.md").read_text()
    assert (tmp_path / "1.1.1.md").read_text().startswith("# 1.1.1\n")
    assert "- [1.1.1: Defamatory content.](1.1.1.md)" in (tmp_path / "1.1.md").read_text()
    index = json.loads((tmp_path / "index.json").read_text())
    assert index["last_updated"] == "2026-06-08"
    assert len(index["sections"]) == len(snapshot.sections)


def test_rejects_unknown_layout() -> None:
    with pytest.raises(ValueError, match="Last Updated"):
        mirror.parse("<html></html>")


def test_drops_last_updated_footer(snapshot: mirror.Snapshot) -> None:
    assert "Last Updated" not in by_slug(snapshot)["after-you-submit"].body


def test_fetch_refuses_plain_http() -> None:
    with pytest.raises(ValueError, match="non-HTTPS"):
        mirror.fetch("http://example.com")
