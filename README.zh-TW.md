<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac 圖示">
  <h1>TokenWatch Mac</h1>
  <p><strong>輕量、低資源占用、適合長期常駐的 macOS 本機 AI 用量與額度中心。</strong></p>
  <p>Codex · Claude Code · Antigravity · OpenCode</p>
</div>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>

## 功能

TokenWatch Mac 是原生選單列應用程式，以**唯讀**方式自動發現並讀取支援的 AI 用戶端本機資料，統一顯示 Token 用量與額度資訊。

- 自動發現 Codex、Claude Code、Antigravity、OpenCode。
- 顯示今日、近 7 天、近 30 天與歷史累計用量。
- 支援 Provider、模型、專案趨勢與額度視窗。
- 具備相應 entitlement 的建置支援驗證式區域網路同步與端對端加密 CloudKit 信箱同步。
- TokenWatch 快照不儲存 prompt、response、工具參數、完整專案路徑或供應商憑證。

## 為長期常駐而最佳化

TokenWatch Mac 針對選單列長期執行進行低開銷設計：

- **Codex 增量索引**：首次建立索引後只讀取新增位元組。
- **FSEvents 事件驅動更新**：白名單 Provider 目錄發生變更時觸發採集，週期更新僅作為備援。
- **有限併發**：限制大型採集器同時執行的數量。
- **語意快照去重**：資料沒有實際變更時，避免重複寫入磁碟、區域網路或 CloudKit。
- **Latest-wins 遠端同步**：只保留最新待同步狀態，避免舊快照累積。
- 原生 Swift / SwiftUI 實作，不依賴內嵌瀏覽器執行環境，也不需要常駐本機 Web Server。

### 參考效能

在約 **810 MB Codex 歷史記錄**上的參考測試：

| 情境 | 最佳化前 | 目前 |
| --- | ---: | ---: |
| 冷啟動完整採集 | 10.10 秒 / ~232 MiB 峰值 | **3.23 秒 / ~127 MiB 峰值** |
| 已有索引 + 新 Codex 資料 | 完整重掃 | **0.86 秒 / ~34 MiB 峰值** |
| 緊接著無變更更新 | 完整重掃 | **0.82 秒 / ~34 MiB 峰值** |

以上資料衡量採集/匯出路徑，並不等同於 App 常駐 RSS；實際表現會隨記錄規模、儲存裝置與硬體而變化。

## 介面截圖

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="TokenWatch Mac Dashboard">
</p>
<p align="center"><sub>Dashboard：用量摘要、專案分布、模型分布與使用趨勢。</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="TokenWatch Mac 選單列面板">
</p>
<p align="center"><sub>選單列面板：滾動用量統計與額度視窗。</sub></p>

## 隱私

- 僅 Mac Hub 讀取本機 AI 用戶端記錄。
- 供應商憑證不會寫入 TokenWatch 快取或跨裝置快照。
- Codex、Claude Code 與 OpenCode 使用本機 Token 計數；Antigravity 的本機記錄不提供權威 Token 計數，因此明確標示為估算值。
- CloudKit 僅在使用者私人資料庫中儲存最新的端對端加密信封。
- 檔案探索範圍限制在已知 Provider 目錄，不會遞迴掃描整個 Home 目錄。

## 安裝

從 **GitHub Releases** 下載最新 DMG。

目前 DMG 為 Universal 建置，採用 ad-hoc 簽署且未經 notarization；macOS 可能顯示 Gatekeeper 提示。CloudKit 遠端同步僅在具備所需 entitlement 的建置中可用。

## 建置

需求：macOS 14+、Xcode、Swift 6.1 toolchain。

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

建置產物位於 `.artifacts/`。

## 原始碼說明

原始碼公開供透明審閱。除非儲存庫中的授權檔案另有明確說明，否則不授予開源授權，保留所有權利。
