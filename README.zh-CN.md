<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac 图标">
  <h1>TokenWatch Mac</h1>
  <p><strong>轻量、低占用、适合长期常驻的 macOS 本地 AI 用量与额度中心。</strong></p>
  <p>Codex · Claude Code · Antigravity · OpenCode</p>
</div>

<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a></p>

## 功能

TokenWatch Mac 是原生菜单栏应用，以**只读**方式自动发现并读取支持的 AI 客户端本地数据，统一展示 Token 用量和额度信息。

- 自动发现 Codex、Claude Code、Antigravity、OpenCode。
- 展示今日、近 7 天、近 30 天和历史累计用量。
- 支持 Provider、模型、项目趋势和额度窗口。
- 完整 entitlement 构建支持认证局域网同步和端到端加密 CloudKit 信箱同步。
- TokenWatch 快照不保存 prompt、response、工具参数、完整项目路径和供应商凭据。

## 为长期常驻而优化

TokenWatch Mac 不是“每隔一分钟重新扫一遍全部日志”的工具，而是围绕常驻运行设计：Codex 使用持久化增量索引，只读新增字节；FSEvents 在白名单目录发生变化时触发刷新；Provider 最多有限并发；无业务变化时不重复写磁盘、局域网或 CloudKit；远程同步采用 latest-wins，不积压旧快照。

### 实测性能

2026-09-04，在约 **810 MB Codex 历史日志**上实测：

| 场景 | 优化前 | 当前 |
| --- | ---: | ---: |
| 冷启动全量采集 | 10.10 秒 / ~232 MiB 峰值 | **3.23 秒 / ~127 MiB** |
| 已有索引 + 新 Codex 数据 | 全量重扫 | **0.86 秒 / ~34 MiB** |
| 紧接着无变化刷新 | 全量重扫 | **0.82 秒 / ~34 MiB** |

以上是采集/导出路径峰值，不等同于 App 常驻 RSS；实际表现会随硬件和日志规模变化。

## 界面截图

稳定版发布前会补充真实 Dashboard 截图。当前自动化环境没有 macOS Screen Recording 权限，因此不会用生成图冒充真实截图。

## 隐私

仅 Mac Hub 读取本地日志；不把供应商凭据写入 TokenWatch 缓存或跨设备快照；CloudKit 只保存用户私有数据库中的最新端到端加密信封；只探测已知客户端目录，不递归扫描整个 Home。

## 安装与构建

从 GitHub Releases 下载 DMG。当前 DMG 是 **Universal Preview**：ad-hoc 签名、未公证，并使用 local-only entitlement，因此该预览二进制不启用 CloudKit 远程同步。正式稳定版应使用 Developer ID 签名并完成 Apple notarization。

```sh
Scripts/bootstrap
Scripts/verify
Scripts/build-mac-dmg
```

源码公开用于透明审阅；除非后续明确提供许可证，否则不授予开源许可，保留全部权利。
