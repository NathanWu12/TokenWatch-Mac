# TokenWatch Mac

**軽量・低負荷で常時起動に適した、macOS ネイティブの AI 使用量 / クォーターハブです。** Codex、Claude Code、Antigravity、OpenCode の標準ローカルデータを読み取り専用で検出し、今日 / 7日 / 30日 / 累計の使用量、モデル・プロジェクト傾向、クォータをまとめて表示します。

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **日本語** · [한국어](README.ko.md) · [Français](README.fr.md) · [Español](README.es.md)

## 常駐向けの設計

Codex は永続インクリメンタル索引で追加されたバイトだけを処理し、FSEvents で許可済み Provider ディレクトリの変更を検出します。収集処理の並列度を制限し、意味のないディスク / LAN / CloudKit 書き込みを省き、リモート同期は latest-wins 方式で古いスナップショットの滞留を防ぎます。Swift / SwiftUI のネイティブ実装で、組み込みブラウザや常駐 Web サーバーは使用しません。

### 参考パフォーマンス

約 **810 MB の Codex 履歴**を使用した参考測定：冷間収集 **3.23秒 / 約127 MiB**、索引作成後の増分収集 **0.86秒 / 約34 MiB**、変更なし **0.82秒 / 約34 MiB**。これらは収集 / エクスポート経路のピーク値であり、アプリの常時 RSS ではありません。

## 小ささと低負荷はアーキテクチャの結果

TokenWatch Mac は **ネイティブ Swift / SwiftUI / AppKit** で実装され、macOS 標準 Framework を直接利用します。現在の Universal Release には **埋め込み Frameworks、Chromium、Electron、Node.js runtime がありません**。

2026-09-05 の実測では、Universal DMG は **5.3 MB**、インストール後の `.app` は **約 11 MB**。約 1.5 時間稼働後のアイドル状態で `top` MEM は **約 45 MB**、6 回連続の 1 秒サンプルは **CPU 0.0% / POWER 0.0** でした。`ps` RSS は共有マッピングを含め **約 121 MiB** です。`POWER` は `top` の相対指標であり、ワット測定ではありません。

Apple の現行 M6 Mac mini 構成（2026-09-05）では、隣接する 8 GB unified memory の差額と 256→512 GB SSD の差額はいずれも **$200**。単なる容量換算として見ると、45 MB は 24 GB の **約 0.19% / 約 $1.1 相当**、11 MB の App は 256 GB の **約 0.004% / 約 $0.01 相当**です。これは実コストの主張ではありません。

Electron v44.0.0 の macOS arm64 runtime ZIP は **約 123.7 MiB**。TokenWatch の 5.3 MB Universal DMG は Intel と Apple Silicon の両方を含みながら、その圧縮 runtime 単体より **約 23 倍小さい**サイズです。これはフレームワーク基準の比較であり、すべての非 Swift アプリや競合アプリが重いという主張ではありません。

Sources: [Apple M6 Mac mini](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Apple configurator](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0](https://github.com/electron/electron/releases/tag/v44.0.0) · [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)

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
