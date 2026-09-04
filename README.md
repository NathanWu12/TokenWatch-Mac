<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac icon">
  <h1>TokenWatch Mac</h1>
  <p><strong>A lightweight, always-on macOS hub for local AI usage and quota tracking.</strong></p>
  <p>Codex · Claude Code · Antigravity · OpenCode</p>
</div>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a>
</p>

## What it does

TokenWatch Mac is a native menu-bar hub that reads the standard local data stores of supported AI clients in **read-only** mode, normalizes token usage and quota information, and presents it in one compact dashboard.

- Automatically discovers supported local AI clients.
- Tracks today / 7-day / 30-day / recorded-all-time token usage.
- Shows provider and model breakdowns, project trends and quota windows.
- Supports authenticated LAN sync and end-to-end encrypted CloudKit mailbox sync for companion clients when the full entitlement-enabled build is used.
- Never stores prompts, responses, tool arguments, complete project paths or provider credentials in TokenWatch snapshots.

## Built to stay open

TokenWatch Mac is designed for **24/7 residency** rather than occasional batch reporting.

- **Incremental Codex indexing** reads only newly appended bytes after the first index build.
- **FSEvents-driven refresh** reacts to changes in whitelisted provider directories; periodic refresh remains only as a safety net.
- **Bounded concurrency** prevents multiple large collectors from inflating memory at the same time.
- **Semantic snapshot deduplication** avoids unnecessary disk, LAN and CloudKit writes when nothing meaningful changed.
- **Latest-wins remote sync** prevents old snapshots from forming an upload backlog.
- Native Swift / SwiftUI implementation, with no embedded browser runtime or always-on local web server.

### Measured collection performance

Measured on the development Mac on **2026-09-04** with approximately **810 MB of Codex history**:

| Scenario | Before optimization | Current |
| --- | ---: | ---: |
| Full cold collection | 10.10 s / ~232 MiB peak | **3.23 s / ~127 MiB peak** |
| New Codex data with existing index | full rescan | **0.86 s / ~34 MiB peak** |
| Immediate no-change collection | full rescan | **0.82 s / ~34 MiB peak** |

These numbers measure the collection/export path, not steady-state application RSS. Actual results vary with log volume, storage and hardware.

## Interface

A real dashboard screenshot will be added before the stable notarized release. Automated publication intentionally does **not** fabricate a UI screenshot when macOS Screen Recording permission is unavailable.

## Privacy first

- Only the Mac hub reads local AI-client logs.
- Provider credentials are not written to TokenWatch caches or cross-device snapshots.
- Codex, Claude Code and OpenCode use local token counters. Antigravity is explicitly labeled as an estimate because its local transcript data does not expose authoritative token counters.
- CloudKit stores only the latest end-to-end encrypted envelope in the user's private database.
- File discovery is restricted to known provider locations; TokenWatch does not recursively crawl the user's home directory.

## Install

Download the latest DMG from **GitHub Releases**.

> **Preview distribution:** the current downloadable DMG is an ad-hoc-signed, non-notarized Universal build because this project machine does not yet have a Developer ID Application certificate. macOS may display a Gatekeeper warning. The preview DMG also uses the local-only entitlement set, so CloudKit remote sync is disabled in that binary. A stable public release should be Developer ID signed and notarized.

## Build

Requirements: macOS 14+, Xcode, Swift 6.1 toolchain.

```sh
Scripts/bootstrap
Scripts/verify
```

Build a local Universal preview ZIP:

```sh
Scripts/build-mac-local-release
```

Build a local Universal DMG:

```sh
Scripts/build-mac-dmg
```

Artifacts are written under `.artifacts/`.

## Source availability

The source is publicly visible for transparency and review. No open-source license is granted unless a license file explicitly says otherwise. All rights are reserved.
