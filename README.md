# app-store-review-kit

An open, machine-readable rulebook of what Apple's App Review checks, plus the tools to keep it current and run it against an app before submission. Not affiliated with or endorsed by Apple.

## Why

Static App Store scanners exist; each one encodes Apple's rules privately and claims broad coverage without saying which guidelines a machine can't check. This repo makes the rules themselves the product:

- **Guidelines mirror** — Apple's App Review Guidelines, one file per section. The git history is the changelog.
- **Rulebook** — every check as data: the guideline it enforces, what evidence it needs (source, binary, plist, privacy manifest, metadata, runtime, or human judgement), severity, and the fix.
- **Coverage map** — every guideline section against the rules that cover it, including the ones that need a human.
- **Engine** — a Swift CLI and Xcode plugin that runs the rulebook against a project or build. Planned.

See the [landscape](docs/landscape.md) review of every comparable tool and the [roadmap](docs/roadmap.md).

## Layout

| Path | Contents |
| --- | --- |
| [`guidelines/`](guidelines/README.md) | Mirror of the App Review Guidelines, plus `index.json` with the section tree |
| `rules/<area>/<name>.toml` | One rule per file; the id is `<area>.<name>` |
| `catalogs/` | Shared reference data: required reason APIs, SDKs that need privacy manifests, purpose strings, app traits, app-type profiles, dated Apple deadlines |
| [`rulebook.json`](rulebook.json) | Every rule and catalog compiled into one file for tools to consume |
| [`COVERAGE.md`](COVERAGE.md) | Every guideline against the rules that cover it |
| `tools/` | `rulebook` Python CLI: mirror, validate, and compile the rulebook |

## Mirror the guidelines

```bash
cd tools
uv sync
uv run rulebook mirror
```

`mirror` fetches the live page, writes one Markdown file per section, and removes sections Apple deleted. Review the diff, then commit it with the date Apple published.

## Rule format

```toml
id = "privacy.required-reason-undeclared"
title = "Required reason API used without a declared reason"
severity = "error"                       # error, warning, or note
evidence = ["source", "binary", "manifest"]
enforced_by = "upload"                   # upload, app-store-connect, or app-review
guidelines = ["5.1.1"]
applies_when = []                        # traits from catalogs/traits.toml; empty means every app
since = "2024-05-01"
itms = ["ITMS-91053"]
summary = "What goes wrong and why Apple cares."
fix = "What to change."
references = ["https://developer.apple.com/..."]

[check]                                  # what a machine can verify
id = "required-reason-apis"
confidence = "medium"                    # high: exact evidence, medium: strong signal, low: heuristic
catalog = "required-reason-apis"

[review]                                 # what a person must judge
questions = ["..."]
```

`evidence` is one or more of `source`, `plist`, `entitlements`, `manifest`, `project`, `binary`, `metadata`, `runtime`, and `human`. A rule with only `[check]` is **automated**, with both is **assisted**, and with only `[review]` is **manual**. `enforced_by` says when the problem surfaces: at upload, in an App Store Connect form, or in App Review.

After editing rules, regenerate the outputs:

```bash
cd tools
uv run rulebook validate && uv run rulebook build && uv run rulebook coverage
```

## Develop

```bash
./scripts/install-hooks.sh   # once per clone: run the gate before every commit
./scripts/check.sh           # lint, types, tests, rule validation, stale-output check
```

## License

[MIT](LICENSE) for the code and rulebook. The guideline text in `guidelines/` is Apple's and stays under Apple's terms.
