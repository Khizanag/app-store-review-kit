#!/bin/sh
# Every gate a commit must pass. Run from anywhere; the pre-commit hook calls it.
# It checks the checkout it is run from, so it works the same in every worktree.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(cd "$(dirname "$(realpath "$0")")/.." && pwd -P)
cd "$root/tools"

uv run --quiet ruff check .
uv run --quiet ruff format --check .
uv run --quiet mypy
uv run --quiet pytest -q --cov=rulebook --cov-fail-under=80 --cov-report=
uv run --quiet rulebook validate
uv run --quiet rulebook build --check
uv run --quiet rulebook coverage --check

cd "$root"
if command -v swift >/dev/null 2>&1; then
    swift build --quiet
    swift test --quiet
fi
if command -v swiftlint >/dev/null 2>&1; then
    swiftlint --strict --quiet
fi
if command -v npx >/dev/null 2>&1; then
    npx --yes markdownlint-cli2 "*.md" "guidelines/*.md" "docs/**/*.md" "skills/**/*.md" >/dev/null
fi
