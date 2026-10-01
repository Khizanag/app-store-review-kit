# Landscape

Every public tool we found that checks an app against App Review before submission, what each does well, and what this repo adopts from it. Reviewed 2026-10-01 by reading every file of each repository. Scores are 1 to 10, averaged over seven axes: Apple coverage breadth, depth and accuracy, determinism and CI readiness, developer experience, reusable data, tests, and docs.

## Scores

| Repository | Shape | License | Stars | Score | Best at |
| --- | --- | --- | --- | --- | --- |
| [berkayturk/appstore-precheck](https://github.com/berkayturk/appstore-precheck) | Shell scanner, agent skill, Action, simulator tier | MIT | 7 | 7.7 | Accuracy discipline: labelled fixtures with a precision floor, confidence per rule, guideline drift hashing |
| [ElxMaj/app-store-review-skill](https://github.com/ElxMaj/app-store-review-skill) | Python scanner plus agent skill, HTML report | MIT | 3 | 7.7 | Evidence-first verdicts, rejection recovery mode, plugin packaging for every agent |
| [Kofiloski/app-store-review-risk](https://github.com/Kofiloski/app-store-review-risk) | Python CLI, Action, skill | MIT | 0 | 7.3 | Target-aware `project.pbxproj` parsing, generated Info.plist keys, diff mode, suppressions with reasons |
| [artbyjazi/app-store-approval](https://github.com/artbyjazi/app-store-approval) | Agent skill with shell checks | MIT | 7 | 6.9 | Sharp rules on third-party AI consent, paywalls, and account deletion |
| [aprilNH7/expo-preflight](https://github.com/aprilNH7/expo-preflight) | Node CLI for Expo | MIT | 0 | 6.9 | Dependency-free PNG icon checks, SDK-to-purpose-string maps |
| [UppercutLabs/heimdall](https://github.com/UppercutLabs/heimdall) | Agent skill, Python helpers | MIT | 0 | 6.3 | `applies_when` conditions per guideline |
| [mjmirza/app-store-compliance](https://github.com/mjmirza/app-store-compliance) | Playbook, JSON patterns, guard hook | Custom royalty license | 350 | 6.1 | Regulatory deadlines calendar, 2026 policy changes, submit-command guard |
| [safaiyeh/app-store-review-skill](https://github.com/safaiyeh/app-store-review-skill) | Agent skill | MIT | 359 | 6.1 | Walks every guideline point in order |
| [RevylAI/greenlight](https://github.com/RevylAI/greenlight) | Go CLI, Homebrew, plugin | MIT | 2,440 | 5.7 | Install experience, SARIF and JUnit output, inline ignores, crypto rules |
| [Kofiloski/ios-release-quality-toolkit](https://github.com/Kofiloski/ios-release-quality-toolkit) | Agent skills | MIT | 0 | 5.6 | Simulator and XCUITest release checks |
| [Sakaax/preflight](https://github.com/Sakaax/preflight) | Swift library and CLI | MIT | 4 | 5.4 | Clean Swift parsing of `.ipa` and `.xcarchive`, merged privacy manifests |
| [CharlesWiltgen/Axiom](https://github.com/CharlesWiltgen/Axiom) (App Store parts) | Agent skills | MIT | 1,185 | 4.9 | App Store Connect reference material |
| [truongduy2611/app-store-preflight-skills](https://github.com/truongduy2611/app-store-preflight-skills) | Agent skill, no code | MIT | 1,376 | 4.7 | One-line install, app-type checklists, real rejection letters, review notes template |
| [setlog-app/expo-plist-audit](https://github.com/setlog-app/expo-plist-audit) | Node script | MIT | 0 | 4.6 | Unused background modes and entitlements |
| [Sakaax/cleared-cli](https://github.com/Sakaax/cleared-cli) | Closed CLI | None | 1 | 4.3 | Baseline ratchet: only new findings fail |
| [delight0517/appstore-release-recovery-skill](https://github.com/delight0517/appstore-release-recovery-skill) | Agent skill | MIT | 0 | 4.1 | Rejection triage and resubmission flow |
| [anagnole/apple-reviewer-simulator](https://github.com/anagnole/apple-reviewer-simulator) | Agent skill driving the simulator | None | 1 | 4.0 | A reviewer's runtime script |
| [hakaru/appstore-review-monitor](https://github.com/hakaru/appstore-review-monitor) | GitHub Action | MIT | 1 | 4.0 | Dependency-free App Store Connect token signing |
| [logiclinelabs/appstore-review-checker](https://github.com/logiclinelabs/appstore-review-checker) | Agent skill | None | 1 | 3.9 | Permission API to purpose string map |

Excluded: one repository tagged `app-store-review` ships a Windows executable inside a zip archive and was not reviewed.

## What the field gets right

- **Something runs.** Every top tool executes checks and returns findings with a file and line. A rulebook alone does not stop a rejection.
- **One-line install.** The most-starred tools install with one command, `brew install` or `npx skills add`, and plug into the agent the developer already uses.
- **Evidence over opinion.** The best scanners report a finding only with the matching code, key, or metadata, mark what they could not check, and fail closed when a check crashes.
- **Accuracy is measured.** berkayturk keeps labelled fixtures per rule with a precision floor and a log of real App Store outcomes.
- **Recovery, not just prevention.** Several skills turn a rejection letter into a fix plan and a Resolution Center reply.

## What the field gets wrong

- **Rules live in code or prompts.** No tool publishes its rules as data another tool can read, so each re-encodes the same checks and repeats the same mistakes.
- **Outdated facts survive.** Several still require Sign in with Apple specifically under 4.8, cite pre-iOS 17 calendar keys, demand retired screenshot sizes, count keywords in characters instead of bytes, or put public APIs on private-API lists.
- **No coverage honesty.** Tools claim "141 guidelines" without saying which ones a machine cannot judge.
- **Noisy heuristics.** Single-word patterns such as `post` or `login` drive findings, and duplicates collapse or explode in reports.

## What we adopt

Ideas are adopted from every repository. Data and code are ported only from MIT-licensed ones, with attribution in [NOTICE](../NOTICE.md).

| Theme | Adopted | From |
| --- | --- | --- |
| Rule schema | Confidence per rule, `applies_when` app traits, app-type profiles, dated deadlines that retire into rules | berkayturk, heimdall, truongduy, mjmirza (idea) |
| Rules | Crypto, UIWebView, cleartext URLs, background modes, review-sensitive entitlements, paywall dark patterns, review prompts, third-party AI consent, VPN, MDM, HealthKit, keyboard full access, loot boxes, external purchase links, AI brands on the China storefront | greenlight, berkayturk, artbyjazi, truongduy, Kofiloski |
| Engine | Target membership from `project.pbxproj` including synchronized folders, generated Info.plist keys, merged privacy manifests, `.ipa` unpacking, PNG icon checks, release-only matching, trigger and safeguard rules | Kofiloski, Sakaax/preflight, aprilNH7, greenlight |
| Developer experience | Inline ignores, strict config file, suppressions with reasons, baseline ratchet, diff mode, fail closed with gap records, SARIF, JUnit, JSON with stable ids | greenlight, Kofiloski, cleared-cli (idea), berkayturk |
| Accuracy | Pass and fail fixtures per rule, precision floor, real-app panel | berkayturk |
| Distribution | Agent skill and plugin manifests, `npx skills add`, Homebrew, GitHub Action, SwiftPM plugin | ElxMaj, safaiyeh, truongduy, greenlight |
| Workflows | Review notes generator, rejection recovery with reply templates | truongduy, ElxMaj, artbyjazi, delight0517 |
| Drift | Per-section fingerprints of the guidelines, deadlines calendar | berkayturk, mjmirza (idea) |
