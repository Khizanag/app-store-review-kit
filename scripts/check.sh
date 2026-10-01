#!/bin/sh
# Every gate a commit must pass. Run from anywhere; the pre-commit hook calls it.
set -eu

root=$(cd "$(dirname "$(realpath "$0")")/.." && pwd -P)
cd "$root/tools"

uv run --quiet ruff check .
uv run --quiet ruff format --check .
uv run --quiet mypy
uv run --quiet pytest -q --cov=rulebook --cov-fail-under=80 --cov-report=
uv run --quiet rulebook validate
uv run --quiet rulebook build --check
uv run --quiet rulebook coverage --check

if command -v npx >/dev/null 2>&1; then
    cd "$root"
    npx --yes markdownlint-cli2 "*.md" "guidelines/*.md" "docs/**/*.md" >/dev/null
fi
