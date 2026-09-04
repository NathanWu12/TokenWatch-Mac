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

## 小體積、低佔用是架構結果

TokenWatch Mac 使用 **原生 Swift / SwiftUI / AppKit** 開發，直接重用 macOS 內建系統 Framework。目前 Universal Release **沒有內嵌 Frameworks 目錄，也不綁定 Chromium、Electron 或 Node.js runtime**。

2026-09-05 對目前公開 Release 的實測：

| 指標 | 實測值 |
| --- | ---: |
| Universal DMG（arm64 + x86_64） | **5.3 MB** |
| 安裝後的 `.app` | **約 11 MB** |
| 主執行檔 | **約 8.0 MB** |
| 內嵌 runtime Framework | **0** |
| 閒置時常駐子程序 | **0** |
| 執行約 1.5 小時後的閒置 `top` MEM | **約 45 MB** |
| 閒置 `ps` RSS | **約 121 MiB** |
| 連續 6 次、每次 1 秒的閒置取樣 | **CPU 0.0% / POWER 0.0** |

同時列出 `top` MEM 與 `ps` RSS，是因為 macOS 不同工具的記憶體計算方式不同；RSS 會包含共享映射，不應直接視為「私人獨佔記憶體」。`POWER 0.0` 是 macOS `top` 的相對程序功耗指標，**不是瓦特數**。較長取樣會看到短暫更新峰值，完成後會立即回到閒置。

### 放到目前 Mac 硬體價格中是什麼量級

截至 **2026-09-05**，Apple 目前 M6 Mac mini 設定器中，相鄰 **8 GB 統一記憶體級距差價為 $200**，**256 GB → 512 GB SSD 差價為 $200**；M6 Mac mini 美國起價為 **$899**。

若只把官方升級價當作方便理解的**容量等價換算**：

- 約 45 MB 閒置 `top` 記憶體僅約為 24 GB 的 **0.19%**；依 $25/GB 的記憶體級距價格換算，約 **$1.1** 的容量。
- 約 11 MB 安裝體積僅佔 256 GB 的 **約 0.004%**；依 Apple SSD 級距價格換算約 **$0.01**。
- 5.3 MB 下載包僅佔 256 GB 的 **約 0.002%**，同口徑換算 **不到半美分**。

這**不是成本會計結論**；Apple 升級價格並不等於 RAM/SSD 製造成本，只是用熟悉的 Mac 價格幫助理解量級。

### 為什麼值得強調原生 Swift

原生方案可以直接使用 macOS 已有的系統 Framework，不需要把瀏覽器 runtime 一起打包。作為量級參考，Electron **v44.0.0** 的 macOS arm64 runtime ZIP 本身就有 **129,743,965 bytes（約 123.7 MiB）**，尚未包含具體 App 自己的程式與資源。TokenWatch 的 **5.3 MB Universal DMG** 同時包含 Apple Silicon 與 Intel 架構，仍比這個 Electron 壓縮 runtime 本身小 **約 23 倍**。

Electron 官方也說明其繼承 Chromium 的多程序模型，包括 main process 與 renderer process。TokenWatch 目前閒置時沒有常駐子程序。這裡比較的是**框架 runtime 基線，不是在聲稱所有非 Swift App 或所有同類專案都很重**；這個領域也有許多優秀的原生 Swift 專案。

資料來源：[Apple M6 Mac mini 發布資訊](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Apple M6 Mac mini 設定器](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0 Release](https://github.com/electron/electron/releases/tag/v44.0.0) · [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model)

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
