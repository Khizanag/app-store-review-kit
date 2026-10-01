#!/bin/sh
# Points this clone's pre-commit hook at scripts/check.sh.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd -P)
hooks=$(git -C "$root" rev-parse --git-common-dir)/hooks
mkdir -p "$hooks"
ln -sf "$root/scripts/check.sh" "$hooks/pre-commit"
echo "pre-commit -> scripts/check.sh"
