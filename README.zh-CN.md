<div align="center">
  <img src="Apps/MacHub/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png" width="128" alt="TokenWatch Mac 图标">
  <h1>TokenWatch Mac</h1>
  <p><strong>原生 Swift · Universal DMG 约 5.3 MB · 空闲 CPU 接近 0 · 为长期常驻而设计。</strong></p>
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

## 小体积、低占用是架构结果

TokenWatch Mac 使用 **原生 Swift / SwiftUI / AppKit** 开发，直接复用 macOS 自带系统 Framework。当前 Universal Release **没有内嵌 Frameworks 目录，不捆绑 Chromium、Electron 或 Node.js 运行时**。

2026-09-05 对当前公开 Release 实测：

| 指标 | 实测值 |
| --- | ---: |
| Universal DMG（arm64 + x86_64） | **5.3 MB** |
| 安装后的 `.app` | **约 11 MB** |
| 主可执行文件 | **约 8.0 MB** |
| 内嵌运行时 Framework | **0** |
| 空闲时常驻子进程 | **0** |
| 运行约 1.5 小时后的空闲 `top` MEM | **约 45 MB** |
| 空闲 `ps` RSS | **约 121 MiB** |
| 连续 6 次、每次 1 秒的空闲采样 | **CPU 0.0% / POWER 0.0** |

这里同时给出 `top` MEM 与 `ps` RSS，因为 macOS 的不同内存工具统计口径不同；RSS 会包含共享映射，不能直接理解为“私有独占内存”。`POWER 0.0` 是 macOS `top` 的相对进程功耗指标，**不是瓦特数**。更长采样会捕捉到短暂刷新峰值，但完成后会立即回到空闲状态。

### 放到当前 Mac 的硬件价格里是什么量级

截至 **2026-09-05**，Apple 当前 M6 Mac mini 配置器中，相邻 **8 GB 统一内存档位差价为 $200**，**256 GB → 512 GB SSD 差价为 $200**；M6 Mac mini 美国起售价为 **$899**。

如果仅把这些官方升级价作为一个便于理解的**容量等价换算**：

- 约 45 MB 空闲 `top` 内存只相当于 24 GB 的 **约 0.19%**；按 $25/GB 的内存档位差价折算，约 **$1.1** 的容量。
- 约 11 MB 安装体积只占 256 GB 的 **约 0.004%**；按 Apple SSD 档位差价折算，约 **$0.01**。
- 5.3 MB 下载包只占 256 GB 的 **约 0.002%**，同口径折算 **不到半美分**。

这**不是成本会计结论**：Apple 的配置升级价不等于 RAM/SSD 的制造成本。这里只是用用户熟悉的 Mac 配置价格帮助理解“到底有多小”。

### 为什么原生 Swift 值得强调

原生方案可以直接使用 macOS 已经安装的系统 Framework，而不需要把浏览器运行时一起打包。作为量级参考，Electron **v44.0.0** 的 macOS arm64 runtime ZIP 本身就有 **129,743,965 bytes（约 123.7 MiB）**，还没有包含具体应用自己的代码与资源。TokenWatch 的 **5.3 MB Universal DMG** 同时包含 Apple Silicon 和 Intel 两套架构，仍然比这个 Electron 压缩运行时本身小 **约 23 倍**。

Electron 官方也明确说明其继承 Chromium 的多进程模型，包括 main process 与 renderer process。TokenWatch 当前空闲时没有常驻子进程。这里比较的是**框架运行时基线，不是在声称所有非 Swift 应用或所有同类项目都很重**；事实上，这个细分领域里也有不少优秀项目采用原生 Swift。

资料来源：[Apple M6 Mac mini 发布信息](https://www.apple.com/newsroom/2026/08/apple-unveils-a-more-powerful-mac-mini-featuring-the-all-new-m6-and-m5-pro/) · [Apple M6 Mac mini 配置器](https://www.apple.com/shop/buy-mac/mac-mini/m6-chip-12-core-cpu-12-core-gpu-24gb-memory-256gb-storage) · [Electron v44.0.0 Release](https://github.com/electron/electron/releases/tag/v44.0.0) · [Electron 进程模型](https://www.electronjs.org/docs/latest/tutorial/process-model)

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
