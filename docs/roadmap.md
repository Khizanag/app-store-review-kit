# Roadmap

The plan to make this the most accurate and most usable App Review checker, built from what the [landscape](landscape.md) review found. Phases run in order; each ships on its own.

## A. Rulebook schema v2

- [ ] `confidence` per rule: `high` fires on exact evidence, `medium` on strong signals, `low` on heuristics.
- [ ] `applies_when` app traits, such as `accounts`, `in-app-purchase`, `subscriptions`, `user-content`, `kids`, `health`, `crypto`, `ai`, `vpn`, `macos`, so a rule only runs for apps it concerns.
- [ ] App-type profiles that select traits, such as subscription app, social app, kids app, game, or AI app.
- [ ] Deadlines catalog: dated Apple requirements, each retired into a rule once it takes effect.
- [ ] Catalogs for review-sensitive entitlements, tracking and ad SDKs, payment SDKs, crypto SDKs, and AI providers.

## B. Rule merge

- [ ] Port the new checks the landscape found, deduplicated and fact-checked against Apple's current documentation. Target: every guideline section either has a rule or is marked as needing a person.
- [ ] Enrich existing rules with the competitors' tested signal lists.
- [ ] Fix nothing by copying: every ported fact is checked against Apple's own pages first.

## C. Swift engine

- [ ] `asrk` CLI and `AppStoreReviewKit` library that run `rulebook.json`, with no third-party dependencies.
- [ ] Parsers: `project.pbxproj` target membership including synchronized folders, build settings and xcconfig, generated `INFOPLIST_KEY_*`, Info.plist, entitlements, privacy manifests merged across the bundle, String Catalogs, `.xcarchive` and `.ipa`, PNG icons, fastlane-style metadata.
- [ ] Matching: release-only code paths, code versus strings and comments, trigger and safeguard rules reported once per project.
- [ ] Findings with stable ids, file and line, rule confidence, and gap records for checks that could not run. Fail closed.
- [ ] Controls: inline `asrk:ignore <rule-id>`, a strict `.asrk.toml` config, suppressions that need a reason, a baseline so only new findings fail, diff mode.
- [ ] Output: terminal, JSON, SARIF, JUnit, and a Markdown review dossier.

## D. Accuracy harness

- [ ] A passing and a failing fixture for every automated rule, run in the commit gate.
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
