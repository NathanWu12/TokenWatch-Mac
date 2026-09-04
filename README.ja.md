# TokenWatch Mac

**軽量・低負荷で常時起動に適した、macOS ネイティブの AI 使用量 / クォーターハブです。** Codex、Claude Code、Antigravity、OpenCode の標準ローカルデータを読み取り専用で検出し、今日 / 7日 / 30日 / 累計の使用量、モデル・プロジェクト傾向、クォータをまとめて表示します。

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **日本語** · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 常駐向けの設計

Codex は永続インクリメンタル索引で追加されたバイトだけを処理し、FSEvents で許可済み Provider ディレクトリの変更を検出します。収集処理の並列度を制限し、意味のないディスク / LAN / CloudKit 書き込みを省き、リモート同期は latest-wins 方式で古いスナップショットの滞留を防ぎます。Swift / SwiftUI のネイティブ実装で、組み込みブラウザや常駐 Web サーバーは使用しません。

### 参考パフォーマンス

約 **810 MB の Codex 履歴**を使用した参考測定：冷間収集 **3.23秒 / 約127 MiB**、索引作成後の増分収集 **0.86秒 / 約34 MiB**、変更なし **0.82秒 / 約34 MiB**。これらは収集 / エクスポート経路のピーク値であり、アプリの常時 RSS ではありません。

## スクリーンショット

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="TokenWatch Mac ダッシュボード">
</p>
<p align="center"><sub>使用量サマリー、プロジェクト別内訳、モデル分布、使用量推移。</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="TokenWatch Mac メニューバーポップオーバー">
</p>
<p align="center"><sub>ローリング使用量とクォータ期間を表示するメニューバーポップオーバー。</sub></p>

## プライバシー

TokenWatch のスナップショットには、prompt、response、ツール引数、完全なプロジェクトパス、プロバイダー資格情報を保存しません。CloudKit には、ユーザーの private database に最新の E2E 暗号化エンベロープだけを保存します。ファイル探索は既知の Provider ディレクトリに限定されます。

## インストール

GitHub Releases から最新の DMG を取得してください。

現在の DMG は Universal ビルドで、ad-hoc 署名かつ未 notarize です。macOS が Gatekeeper の警告を表示する場合があります。CloudKit リモート同期は、必要な entitlement を備えたビルドでのみ利用できます。

## ビルド

要件：macOS 14+、Xcode、Swift 6.1 toolchain。

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

## ソースコード

ソースコードは透明性とレビューのため公開されています。リポジトリ内のライセンスファイルに明示がない限り、オープンソースライセンスは付与されません。
