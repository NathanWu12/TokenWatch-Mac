# TokenWatch Mac

**軽量・低負荷で、常時起動に向いた macOS ネイティブ AI 使用量 / クォーターハブ。**  Codex、Claude Code、Antigravity、OpenCode の標準ローカルデータを読み取り専用で検出し、今日 / 7日 / 30日 / 累計の使用量、モデル・プロジェクト傾向、クォータをまとめて表示します。

[English](README.md) · [简体中文](README.zh-CN.md) · **日本語** · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 常駐向けの設計

Codex は永続インクリメンタル索引で追加バイトだけを処理し、FSEvents で変更を検出、並列度を制限し、意味のない再書き込みや古い CloudKit スナップショットの滞留を避けます。Swift / SwiftUI のネイティブ実装で、組み込みブラウザや常駐 Web サーバーはありません。

約 810 MB の Codex 履歴での実測（2026-09-04）：冷間収集 **3.23秒 / 約127 MiB**、索引作成後の増分収集 **0.86秒 / 約34 MiB**、変更なし **0.82秒 / 約34 MiB**。これは収集経路のピーク値で、常時 RSS ではありません。

## プライバシー

prompt、response、ツール引数、完全なプロジェクトパス、プロバイダー資格情報を TokenWatch スナップショットへ保存しません。CloudKit は private database に最新の E2E 暗号化エンベロープだけを保存します。

## インストール

GitHub Releases から DMG を取得してください。現在の Preview DMG は ad-hoc 署名・未 notarize で、local-only entitlement のため CloudKit リモート同期は無効です。安定公開版は Developer ID 署名 + notarization を予定しています。

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

実画面スクリーンショットは notarized stable release 前に追加します。ソースは透明性のため公開されていますが、明示的な LICENSE がない限りオープンソースライセンスは付与されません。
