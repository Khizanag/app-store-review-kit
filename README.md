# app-store-review-kit

Check an iOS app against Apple's App Review Guidelines before you submit, from an open, machine-readable rulebook that says exactly what a machine can check and what still needs a person. Not affiliated with or endorsed by Apple.

## Install

Pick the one that fits how you work. Every option runs locally; nothing about your app leaves your machine.

| Where | Install | Then |
| --- | --- | --- |
| Terminal | `brew tap khizanag/asrk https://github.com/Khizanag/app-store-review-kit && brew trust --formula khizanag/asrk/asrk && brew install asrk` | `asrk check path/to/YourApp` |
| Claude Code | `/plugin marketplace add Khizanag/app-store-review-kit` then `/plugin install app-store-review@app-store-review-kit` | "Check this app before I submit." |
| Any agent with skills | `npx skills add Khizanag/app-store-review-kit` | "My app was rejected under 5.1.1; what do I change?" |
| GitHub Actions | `uses: Khizanag/app-store-review-kit@v0.1.0`, [below](#in-ci) | Findings in code scanning |
| From source | `git clone https://github.com/Khizanag/app-store-review-kit && swift build -c release` | `.build/release/asrk check …` |

`asrk` needs macOS with Xcode 26 or later. The agent skill runs `asrk`, verifies each finding in your code, answers the review questions a machine cannot, drafts Resolution Center replies after a rejection, and writes your Notes for App Review.

## Why

Static App Store scanners exist; each one encodes Apple's rules privately and claims broad coverage without saying which guidelines a machine can't check. This repo makes the rules themselves the product:

- **Guidelines mirror** — Apple's App Review Guidelines, one file per section. The git history is the changelog.
- **Rulebook** — every check as data: the guideline it enforces, what evidence it needs (source, binary, plist, privacy manifest, metadata, runtime, or human judgement), how confident a match is, severity, and the fix.
- **Coverage map** — every guideline section against the rules that cover it, including the ones that need a human.
- **Engine** — `asrk`, a dependency-free Swift CLI that runs the rulebook against a project and reports findings as text, JSON, or SARIF.

See the [landscape](docs/landscape.md) review of every comparable tool and the [roadmap](docs/roadmap.md).

## Check an app

Point `asrk` at the folder that holds your Xcode project:

```bash
asrk check .                              # human-readable report
asrk check . --format sarif > asrk.sarif  # GitHub code scanning
asrk check . --format json                # for scripts and agents
asrk check . --profile subscription       # declare the app type when signals are thin
asrk check . --fail-on warning            # exit 1 on warnings too; default is errors only
```

It reads the app target's Release build settings, including generated `INFOPLIST_KEY_*` values, Info.plist, entitlements, privacy manifests, String Catalogs, `Package.resolved` and `Podfile.lock`, Swift and Objective-C sources, and fastlane-style `metadata/<locale>/*.txt` store text. Code inside `#if DEBUG`, comments, and interpolated expressions never trigger findings.

The report has three parts:

- **Findings** — automated matches, each with the rule, its guideline, a confidence level, the files and lines, and the fix.
- **Needs a person** — rules that apply to this app but need judgement, with the questions to answer.
- **Skipped** — rules that could not run, and why, such as a check that needs a built binary. A skipped rule is never reported as passed.

Rules only run for apps they concern. `asrk` detects traits such as accounts, in-app purchase, subscriptions, user content, AI, or advertising from the code; set them with `--profile` or `--trait` when detection misses one.

Silence a single finding with a comment on the line or the line above:

```swift
let staging = URL(string: "https://staging.example.com") // asrk:ignore build.debug-endpoints
```

Exit codes: `0` nothing at or above `--fail-on`, `1` findings at or above it, `2` a usage error.

### In CI

The action builds `asrk` once per version, caches it, writes SARIF, and puts the summary on the run page. It needs a macOS runner with Xcode 26.

```yaml
jobs:
  app-review:
    runs-on: macos-26
    permissions:
      contents: read
      security-events: write
    steps:
      - uses: actions/checkout@v4
      - uses: Khizanag/app-store-review-kit@v0.1.0
        with:
          fail-on: error           # or warning, note, never
          profile: subscription    # optional
      - uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: asrk.sarif
```

Other inputs: `path` for the project folder, `target` when the project has several apps, `sarif-file` to rename or skip the SARIF output.

## Layout

| Path | Contents |
| --- | --- |
| [`guidelines/`](guidelines/README.md) | Mirror of the App Review Guidelines, plus `index.json` with the section tree |
| `rules/<area>/<name>.toml` | One rule per file; the id is `<area>.<name>` |
| `catalogs/` | Shared reference data: required reason APIs, SDKs that need privacy manifests, purpose strings, privacy manifest keys, app traits, app-type profiles, dated Apple deadlines |
| [`rulebook.json`](rulebook.json) | Every rule and catalog compiled into one file for tools to consume |
| [`COVERAGE.md`](COVERAGE.md) | Every guideline against the rules that cover it |
| `Sources/` | `AppStoreReviewKit` library and the `asrk` CLI |
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

After editing rules, regenerate the outputs, including the copy of the rulebook compiled into `asrk`:

```bash
cd tools
uv run rulebook validate && uv run rulebook build && uv run rulebook coverage
```

## Develop

```bash
./scripts/install-hooks.sh   # once per clone: run the gate before every commit
./scripts/check.sh           # Python and Swift lint, types, tests, rule validation, stale-output check
```

## License

[MIT](LICENSE) for the code and rulebook. The guideline text in `guidelines/` is Apple's and stays under Apple's terms.
