from pathlib import Path

import pytest

from rulebook.cli import main

FIXTURE = Path(__file__).parent / "fixtures" / "guidelines.html"


def test_mirror_writes_from_saved_page(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    assert main(["mirror", "--source", str(FIXTURE), "--out", str(tmp_path)]) == 0
    assert (tmp_path / "1.1.md").exists()
    assert "7 sections, last updated 2026-06-08" in capsys.readouterr().out
