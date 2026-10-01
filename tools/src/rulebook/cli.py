from __future__ import annotations

import argparse
from pathlib import Path

from rulebook import mirror

REPO_ROOT = Path(__file__).resolve().parents[3]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="rulebook")
    commands = parser.add_subparsers(dest="command", required=True)

    mirror_command = commands.add_parser("mirror", help="Mirror Apple's App Review Guidelines.")
    mirror_command.add_argument("--source", type=Path, help="Saved HTML page instead of fetching.")
    mirror_command.add_argument("--out", type=Path, default=REPO_ROOT / "guidelines")

    args = parser.parse_args(argv)
    match args.command:
        case "mirror":
            html = args.source.read_text() if args.source else mirror.fetch()
            snapshot = mirror.parse(html)
            mirror.write(snapshot, args.out)
            print(f"{len(snapshot.sections)} sections, last updated {snapshot.last_updated}")
    return 0
