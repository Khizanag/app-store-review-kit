from __future__ import annotations

import argparse
import sys
from collections.abc import Callable
from pathlib import Path

from rulebook import coverage, mirror
from rulebook.build import SWIFT_PATH, compile_rulebook, compile_swift
from rulebook.model import Rulebook, RulebookError, load

REPO_ROOT = Path(__file__).resolve().parents[3]

Generator = Callable[[Rulebook], str]
GENERATED: dict[str, tuple[tuple[str, Generator], ...]] = {
    "build": (("rulebook.json", compile_rulebook), (SWIFT_PATH, compile_swift)),
    "coverage": (("COVERAGE.md", coverage.render),),
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="rulebook")
    parser.add_argument("--root", type=Path, default=REPO_ROOT, help="Repository root.")
    commands = parser.add_subparsers(dest="command", required=True)

    mirror_command = commands.add_parser("mirror", help="Mirror Apple's App Review Guidelines.")
    mirror_command.add_argument("--source", type=Path, help="Saved HTML page instead of fetching.")
    mirror_command.add_argument(
        "--out", type=Path, help="Output folder; default <root>/guidelines."
    )

    commands.add_parser("validate", help="Validate every rule and catalog.")
    for name, outputs in GENERATED.items():
        files = ", ".join(output for output, _ in outputs)
        command = commands.add_parser(name, help=f"Write {files}.")
        command.add_argument("--check", action="store_true", help=f"Fail if {files} is stale.")

    args = parser.parse_args(argv)
    root: Path = args.root
    if args.command == "mirror":
        html = args.source.read_text() if args.source else mirror.fetch()
        snapshot = mirror.parse(html)
        mirror.write(snapshot, args.out or root / "guidelines")
        print(f"{len(snapshot.sections)} sections, last updated {snapshot.last_updated}")
        return 0

    try:
        rulebook = load(root)
    except RulebookError as error:
        for problem in error.problems:
            print(problem, file=sys.stderr)
        return 1

    if args.command == "validate":
        print(f"{len(rulebook.rules)} rules, {len(rulebook.catalogs)} catalogs: valid")
        return 0

    stale = False
    for output, generate in GENERATED[args.command]:
        target = root / output
        content = generate(rulebook)
        if args.check:
            if not target.exists() or target.read_text() != content:
                print(f"{output} is stale; run `uv run rulebook {args.command}`", file=sys.stderr)
                stale = True
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        print(f"Wrote {output}")
    return 1 if stale else 0
