<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac 图标">
  <h1>TokenWatch Mac</h1>
  <p><strong>轻量、低占用、适合长期常驻的 macOS 本地 AI 用量与额度中心。</strong></p>
  <p>Codex · Claude Code · Antigravity · OpenCode</p>
</div>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>

## 功能

TokenWatch Mac 是原生菜单栏应用，以**只读**方式自动发现并读取支持的 AI 客户端本地数据，统一展示 Token 用量和额度信息。

- 自动发现 Codex、Claude Code、Antigravity、OpenCode。
- 展示今日、近 7 天、近 30 天和历史累计用量。
- 支持 Provider、模型、项目趋势和额度窗口。
- 具备相应 entitlement 的构建支持认证局域网同步和端到端加密 CloudKit 信箱同步。
- TokenWatch 快照不保存 prompt、response、工具参数、完整项目路径和供应商凭据。

## 为长期常驻而优化

TokenWatch Mac 针对菜单栏长期运行进行了低开销设计：

- **Codex 增量索引**：首次建立索引后仅读取新增字节。
- **FSEvents 事件驱动刷新**：白名单 Provider 目录发生变化时触发采集，周期刷新仅作为兜底。
- **有限并发**：限制大型采集器同时运行的数量。
- **语义快照去重**：业务数据没有实际变化时，避免重复写入磁盘、局域网或 CloudKit。
- **Latest-wins 远程同步**：只保留最新待同步状态，避免旧快照积压。
- 原生 Swift / SwiftUI 实现，不依赖内嵌浏览器运行时，也不需要常驻本地 Web Server。

### 参考性能

在约 **810 MB Codex 历史日志**上的参考测试：

| 场景 | 优化前 | 当前 |
| --- | ---: | ---: |
| 冷启动全量采集 | 10.10 秒 / ~232 MiB 峰值 | **3.23 秒 / ~127 MiB 峰值** |
| 已有索引 + 新 Codex 数据 | 全量重扫 | **0.86 秒 / ~34 MiB 峰值** |
| 紧接着无变化刷新 | 全量重扫 | **0.82 秒 / ~34 MiB 峰值** |

以上数据衡量采集/导出路径，并不等同于 App 常驻 RSS；实际表现会随日志规模、存储和硬件变化。

## 界面截图

<p align="center">
  <img src="docs/images/dashboard.webp" width="900" alt="TokenWatch Mac Dashboard">
</p>
<p align="center"><sub>Dashboard：用量汇总、项目分布、模型分布与使用趋势。</sub></p>

<p align="center">
  <img src="docs/images/menu-bar.webp" width="560" alt="TokenWatch Mac 菜单栏面板">
</p>
<p align="center"><sub>菜单栏面板：滚动用量统计与额度窗口。</sub></p>

## 隐私

- 仅 Mac Hub 读取本地 AI 客户端日志。
- 供应商凭据不会写入 TokenWatch 缓存或跨设备快照。
- Codex、Claude Code 和 OpenCode 使用本地 Token 计数；Antigravity 的本地记录不提供权威 Token 计数，因此明确标记为估算值。
- CloudKit 仅在用户私有数据库中保存最新的端到端加密信封。
- 文件发现范围限制在已知 Provider 目录，不递归扫描整个 Home 目录。

## 安装

从 **GitHub Releases** 下载最新 DMG。

当前 DMG 为 Universal 构建，采用 ad-hoc 签名且未公证；macOS 可能显示 Gatekeeper 提示。CloudKit 远程同步仅在具备所需 entitlement 的构建中可用。

## 构建

要求：macOS 14+、Xcode、Swift 6.1 toolchain。

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

构建产物位于 `.artifacts/`。

## 源码说明

源码公开用于透明审阅。除非仓库中的许可证文件另有明确说明，否则不授予开源许可，保留全部权利。
