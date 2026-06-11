<div align="center">
  <img src="Resources/icon-512.png" width="140" alt="Grañipa 图标">

  # Grañipa

  **完全本地、开源的 macOS 会议笔记应用 — 还附带你一直在为之付费订阅的效率工具。**

  ![macOS 26+](https://img.shields.io/badge/macOS-26%2B-blue)
  ![Swift 6](https://img.shields.io/badge/Swift-6-F05423)
  ![License: MIT](https://img.shields.io/badge/License-MIT-green)
  ![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

  [English](README.md) | **简体中文**
</div>

---

Grañipa 可以录制你的会议（无需机器人加入通话）、在设备端实时转写、识别每句话的发言人、用 AI 把你的粗略笔记整理成结构化笔记，并把所有内容推送到你自己的服务 — 同时还能取代你的剪贴板管理器、OCR 工具和窗口管理器。

**无账户。无云端。无订阅。** 除非*你*主动发送，你的数据永远不会离开你的 Mac。

> 这是 Granola（每月 14 美元）、Raycast 剪贴板历史、TextSniper 和 Rectangle 的个人自建替代品 — 集成在一个原生应用里。

<p align="center">
  <img src="docs/home.png" width="760" alt="Grañipa 主页 — 按日期组织的会议">
</p>

## 功能

### 🎙 会议

- **无机器人录制** — 通过 Core Audio process tap 将你的麦克风和系统音频（其他参会者）作为两条独立干净的音轨捕获。适用于 Zoom、Meet、Teams、Webex 等任何会播放声音的应用。
- **设备端实时转写** — Apple SpeechAnalyzer（macOS 26），逐词流式输出。免费且离线。
- **自动语言检测** — 可选最多 3 种语言（Apple 引擎支持 15+ 种）；每次录制的前几秒并行探测，自动保留匹配的那个。
- **说话人分离（Diarization）** — 在本地（CoreML）把远端参会者分为 Speaker 1/2/3，再根据对话上下文推断他们的真实姓名。
- **AI 增强笔记** — 你的粗略笔记 + 会议转写 = 结构化笔记、摘要、行动项，以及一封可直接发送的跟进邮件。还会自动为会议命名。
- **使用你已有的 AI 订阅** — 直接调用你已付费的 `claude`、`codex`、`gemini` 或 `grok` 命令行工具。**不需要 API key，没有按 token 计费。**
- **模板** — 按会议类型定制提示词（1:1、站会、销售电话……），完全可编辑。
- **文件夹与团队** — 像 Granola 一样组织会议；目录结构同样暴露在 API 中。
- **日历集成** — 在应用内查看即将开始的会议，一键录制，自动以日历事件命名。
- **自动检测** — 发现会议应用开始使用麦克风时提示录制；通话结束时可自动停止。
- **搜索** — 对标题、笔记和转写内容全文搜索。

### 🧰 效率工具

- **剪贴板历史**（`⌥⇧V`）— Raycast 风格的浮动面板：搜索、类型筛选、图片预览、来源应用、自动粘贴到当前应用。尊重密码管理器的保密标记。100% 本地。
- **屏幕文字识别 / OCR**（`⌥⇧T`）— 框选任意屏幕区域，文字直接进入剪贴板（Vision 框架，识别语言跟随你的语言设置）。
- **窗口管理**（`⌃⌥` + 方向键/字母）— 与 Rectangle 兼容的快捷键：左右/上下半屏、四分之一、三分之一、最大化、居中、还原。

### 🔌 集成

- **本地 REST API** — `127.0.0.1:7799`，Bearer token 认证：会议、转写、笔记、文件夹、触发 AI 增强。
- **Webhooks** — 在 `meeting.started`、`meeting.completed`（含完整转写）、`notes.enhanced` 时发送带 HMAC-SHA256 签名的 POST 请求，失败自动重试。

## 系统要求

- **macOS 26+**（Apple Silicon）。
- Xcode 26 工具链（从源码构建时需要）。
- 至少安装并登录一个 AI 命令行工具：[Claude Code](https://docs.anthropic.com/claude-code)、OpenAI Codex、Gemini CLI 或 Grok — 仅笔记增强需要；录制和转写无需任何 AI 工具。

## 安装

### 下载（推荐）

从 [Releases](../../releases) 下载最新的公证版本，解压后把 **Grañipa.app** 拖入 `/Applications`。已签名并经过 Apple 公证 — 没有任何 Gatekeeper 警告。

### 从源码构建

```sh
git clone https://github.com/Zertyn-Enterprises/granipa.git
cd granipa
./Scripts/bundle.sh release
open "build/Grañipa.app"
```

### 首次运行权限

| 权限提示 | 用途 | 时机 |
|---|---|---|
| 麦克风 | 你这一侧的声音 | 首次录制 |
| 系统音频录制 | 其他参会者的声音 | 首次录制 |
| 日历 | 侧边栏显示即将开始的会议 | 启动时 |
| 通知 | "检测到会议 — 录制吗？" | 启动时 |
| 屏幕录制 | OCR 截取（`⌥⇧T`） | 首次使用 OCR |
| 辅助功能 | 自动粘贴 + 窗口管理 | 首次使用 |

每种语言首次录制时，macOS 会下载一次语音模型。首次多人会议时会从 HuggingFace 下载一次说话人分离模型（约 130 MB），之后完全离线运行。

## REST API

Bearer token 在 设置 → API 中。

```sh
TOKEN=...
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings/<id>/transcript
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/folders
curl -X POST -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7799/v1/meetings/<id>/enhance
```

## 隐私

- 音频、转写、笔记和剪贴板历史都存放在 `~/Library/Application Support/Granipa/`（SQLite + 文件）。删除该文件夹，一切都会消失。
- **唯一**会离开你 Mac 的数据：AI 增强时发送给*你*配置的 AI 命令行工具的转写内容，以及发送到*你*添加的 URL 的 webhook 数据。
- 无遥测、无分析、无账户、无自动更新。

## 开发

```sh
swift build         # 编译
swift test          # 64 个测试：存储、API、webhooks、语言检测、窗口布局……
./Scripts/bundle.sh # 调试版 .app
```

贡献者（以及 AI agent）的架构说明见 [CLAUDE.md](CLAUDE.md)。欢迎 PR — 见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 常见问题

**转写一直是空的，或者只有我自己的声音被转写。**
请授予 *系统音频录制* 权限（系统设置 → 隐私与安全性 → 屏幕与系统音频录制），然后停止并**重新开始**一次录制。系统音频只在会议应用实际播放声音时才会流动。如果你用临时签名（ad-hoc）从源码构建，macOS 每次重新构建都会忘记权限 — 请使用真实证书。

**会议结束后提示 "Enhancement failed"。**
所选的 AI 命令行工具未安装或未登录。在终端里运行一次（例如 `claude`）并完成登录，然后确认 设置 → AI 中显示已检测到。

**窗口管理或剪贴板快捷键不起作用。**
其他应用占用了这些快捷键 — 退出 Rectangle（相同的 ⌃⌥ 方案）或检查 Raycast 的自定义快捷键，然后重启 Grañipa。自动粘贴和窗口管理还需要辅助功能权限。

**我的数据在哪里？如何删除？**
所有数据都在 `~/Library/Application Support/Granipa/`。删除该文件夹即可全部清除。

## 致谢

- [GRDB.swift](https://github.com/groue/GRDB.swift)（MIT）— 存储。
- [FluidAudio](https://github.com/FluidInference/FluidAudio)（Apache-2.0）— 说话人分离。其 CoreML 模型源自 [pyannote](https://github.com/pyannote/pyannote-audio)，采用 CC-BY-4.0 许可。
- [AudioCap](https://github.com/insidegui/AudioCap) 与 Apple 官方 Core Audio taps 示例 — 系统音频捕获的参考实现。
- [Granola](https://granola.ai)、[Raycast](https://raycast.com) 与 [Rectangle](https://rectangleapp.com) — 灵感来源。想要精致且有支持的产品就付费支持它们；想要本地且完全属于自己的就用这个。

Granola、Raycast、Rectangle、TextSniper 及文中提到的其他产品名称均为其各自所有者的商标。Grañipa 是独立项目，与上述任何公司均无关联，也未获得其认可。

## 许可证

[MIT](LICENSE)
