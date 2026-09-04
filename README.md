<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac icon">
  <h1>TokenWatch Mac</h1>
  <p><strong>A lightweight, always-on macOS hub for local AI usage and quota tracking.</strong></p>
  <p>Codex · Claude Code · Antigravity · OpenCode</p>
</div>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a>
</p>

## What it does

TokenWatch Mac is a native menu-bar application that reads the standard local data stores of supported AI clients in **read-only** mode, normalizes token usage and quota information, and presents it in a compact dashboard.

- Automatically discovers supported local AI clients.
- Tracks today, 7-day, 30-day and recorded-all-time token usage.
- Shows provider and model breakdowns, project trends and quota windows.
- Supports authenticated LAN sync and end-to-end encrypted CloudKit mailbox sync for companion clients when the entitlement-enabled build is used.
- Does not store prompts, responses, tool arguments, complete project paths or provider credentials in TokenWatch snapshots.

## Designed for continuous operation

TokenWatch Mac is optimized for long-running menu-bar use with low collection overhead.

- **Incremental Codex indexing** reads only newly appended bytes after the initial index is built.
- **FSEvents-driven refresh** reacts to changes in approved provider directories, with periodic refresh retained as a fallback.
- **Bounded concurrency** limits simultaneous large collectors.
- **Semantic snapshot deduplication** avoids unnecessary disk, LAN and CloudKit writes when data has not meaningfully changed.
- **Latest-wins remote sync** prevents obsolete snapshots from building an upload backlog.
- Native Swift / SwiftUI implementation with no embedded browser runtime or always-on local web server.

### Reference collection performance

Reference benchmark using approximately **810 MB of Codex history**:

| Scenario | Before optimization | Current |
| --- | ---: | ---: |
| Full cold collection | 10.10 s / ~232 MiB peak | **3.23 s / ~127 MiB peak** |
| New Codex data with existing index | full rescan | **0.86 s / ~34 MiB peak** |
| Immediate no-change collection | full rescan | **0.82 s / ~34 MiB peak** |

These figures measure the collection/export path rather than steady-state application RSS. Results vary with log volume, storage and hardware.

## Screenshots

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="TokenWatch Mac dashboard">
</p>
<p align="center"><sub>Dashboard with usage summaries, project breakdown, model distribution and usage trends.</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="TokenWatch Mac menu-bar popover">
</p>
<p align="center"><sub>Menu-bar popover with rolling usage totals and quota windows.</sub></p>

## Privacy

- Only the Mac hub reads local AI-client logs.
- Provider credentials are not written to TokenWatch caches or cross-device snapshots.
- Codex, Claude Code and OpenCode use local token counters. Antigravity is labeled as an estimate because its local transcript data does not expose authoritative token counters.
- CloudKit stores only the latest end-to-end encrypted envelope in the user's private database.
- File discovery is restricted to known provider locations; TokenWatch does not recursively crawl the user's home directory.

## Install

Download the latest DMG from **GitHub Releases**.

Current DMG builds are Universal, ad-hoc signed and not notarized; macOS may display a Gatekeeper warning. CloudKit remote sync is available only in builds with the required entitlements.

## Build

Requirements: macOS 14+, Xcode and the Swift 6.1 toolchain.

```sh
Scripts/bootstrap
Scripts/verify
```

Build a local Universal ZIP:

```sh
Scripts/build-mac-local-release
```

Build a local Universal DMG:

```sh
Scripts/build-mac-dmg
```

Artifacts are written under `.artifacts/`.

## Source availability

The source is publicly visible for transparency and review. No open-source license is granted unless a license file explicitly states otherwise. All rights are reserved.
