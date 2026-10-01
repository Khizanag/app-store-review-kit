# Roadmap

The plan to make this the most accurate and most usable App Review checker, built from what the [landscape](landscape.md) review found. Phases run in order; each ships on its own.

## A. Rulebook schema v2

- [x] `confidence` per check: `high` fires on exact evidence, `medium` on strong signals, `low` on heuristics.
- [x] `applies_when` app traits, such as `accounts`, `in-app-purchase`, `subscriptions`, `user-content`, `kids`, `health`, `crypto`, `ai`, `vpn`, `macos`, so a rule only runs for apps it concerns.
- [x] App-type profiles that select traits, such as subscription app, social app, kids app, game, or AI app.
- [x] Deadlines catalog: dated Apple requirements, each retired into a rule once it takes effect.
- [x] Catalogs for review-sensitive entitlements, tracking and ad SDKs, crypto SDKs, external purchase entitlements, privacy manifest keys, and screenshot sizes.

## B. Rule merge

- [x] Port the new checks the landscape found, deduplicated and fact-checked against Apple's current documentation. Every guideline section has a rule, a rule in its subsections, or is marked omitted by Apple.
- [x] Enrich existing rules with the competitors' tested signal lists, credited in [NOTICE](../NOTICE.md).
- [ ] Turn the most common `[review]`-only rules into assisted checks as the engine learns new evidence.

## C. Swift engine

- [x] `asrk` CLI and `AppStoreReviewKit` library that run the embedded rulebook, with no third-party dependencies.
- [x] Parsers: `project.pbxproj` application targets and Release build settings, generated `INFOPLIST_KEY_*`, Info.plist, entitlements, privacy manifests, String Catalogs, `Package.resolved`, `Podfile.lock`, fastlane-style metadata.
- [ ] Parsers: target membership including synchronized folders, xcconfig files, `.xcarchive` and `.ipa`, Mach-O load commands and symbols, PNG icons, `embedded.mobileprovision`.
- [x] Matching: release-only code paths, code versus strings and comments, whole-word terms, trigger and safeguard rules reported once per project.
- [x] Findings with stable ids, file and line, rule confidence; skipped rules with the reason; low-confidence signals routed to a person's review instead of failing the build.
- [x] Inline `asrk:ignore <rule-id>`.
- [ ] A strict `.asrk.toml` config, suppressions that need a reason, a baseline so only new findings fail, diff mode.
- [x] Output: terminal, JSON, SARIF.
- [ ] Output: JUnit and a Markdown review dossier.

## D. Accuracy harness

- [x] Fixtures for the tokenizer, the parsers, and each family of checks, run in the commit gate.
- [ ] A passing and a failing fixture for every automated rule.
- [ ] A precision floor per rule, measured on a panel of real projects kept outside the repo.

## E. Distribution

- [ ] Agent skill (`SKILL.md`) and plugin manifests for Claude Code, Codex, Cursor, and Copilot; `npx skills add` install.
- [ ] Homebrew formula and a composite GitHub Action that runs in the user's own CI.
- [ ] SwiftPM command plugin and Xcode build tool plugin.
- [ ] MCP server mode.

## F. Workflows

- [ ] Review notes generator built from the rules that apply.
- [ ] Rejection recovery: map a rejection letter to rules, plan the fix, and draft a Resolution Center reply.

## G. Drift

- [ ] Per-section fingerprints of the guidelines and a scheduled local job that flags rules whose sections changed.

## H. Runtime reviewer

- [ ] XCUITest run on a pinned simulator: cold launch offline, demo login, account deletion up to the final confirmation, restore purchases, iPad layout, permission timing.
