# app-store-review-kit

An open, machine-readable rulebook of what Apple's App Review checks, plus the tools to keep it current and run it against an app before submission. Not affiliated with or endorsed by Apple.

## Why

Static App Store scanners exist; each one encodes Apple's rules privately and claims broad coverage without saying which guidelines a machine can't check. This repo makes the rules themselves the product:

- **Guidelines mirror** — Apple's App Review Guidelines, one file per section. The git history is the changelog.
- **Rulebook** — every check as data: the guideline it enforces, what evidence it needs (source, binary, plist, privacy manifest, metadata, runtime, or human judgement), severity, and the fix.
- **Coverage map** — every guideline section against the rules that cover it, including the ones that need a human.
- **Engine** — a Swift CLI and Xcode plugin that runs the rulebook against a project or build. Planned.

## Layout

| Path | Contents |
| --- | --- |
| [`guidelines/`](guidelines/README.md) | Mirror of the App Review Guidelines, plus `index.json` with the section tree |
| `tools/` | `rulebook` Python CLI: mirror, validate, and compile the rulebook |

## Mirror the guidelines

```bash
cd tools
uv sync
uv run rulebook mirror
```

`mirror` fetches the live page, writes one Markdown file per section, and removes sections Apple deleted. Review the diff, then commit it with the date Apple published.

## Develop

```bash
cd tools
uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest --cov=rulebook
```

## License

[MIT](LICENSE) for the code and rulebook. The guideline text in `guidelines/` is Apple's and stays under Apple's terms.
