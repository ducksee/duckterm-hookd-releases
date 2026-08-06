<p align="center">
  <img src="./assets/duckterm-mark.svg" width="72" height="72" alt="DuckTerm">
</p>

<h1 align="center">DuckTerm Hookd</h1>

<p align="center">
  <strong>Agent 留在电脑上持续工作，你在手机上随时接手。</strong>
</p>

<p align="center">
  <a href="./README.md">English</a> · 简体中文
</p>

<p align="center">
  <a href="https://github.com/ducksee/duckterm-hookd-releases/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/ducksee/duckterm-hookd-releases?display_name=tag&style=flat-square"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-Apple%20silicon%20%7C%20Intel-111827?style=flat-square&logo=apple">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-x64%20%7C%20arm64-0078D4?style=flat-square&logo=windows11&logoColor=white">
  <img alt="Linux 和 WSL" src="https://img.shields.io/badge/Linux%20%7C%20WSL-x64%20%7C%20arm64-FCC624?style=flat-square&logo=linux&logoColor=111827">
</p>

Hookd 是运行在电脑上的轻量伴随服务，它把本机的编程 Agent 与 iPhone、iPad
和 Android 上的 DuckTerm 连起来。Agent 和终端仍在原来的机器上运行；手机
负责接收通知、处理授权、发送回复，并在需要上下文时查看实时终端。

它适合把长时间任务留在工作站、服务器或 Windows 电脑上的开发者。Hookd
不会把 Agent 搬进托管 Shell，也不是一个公开的终端网关。

## 先安装手机 App

先在随身携带的手机或平板上安装 DuckTerm。iOS/iPadOS 与 Android 使用同一套
Hookd 配对流程。

<p align="center">
  <a href="https://apps.apple.com/app/id6766765739"><img src="./assets/app-store-badge.svg" height="56" alt="在 App Store 下载 DuckTerm"></a>
  &nbsp;&nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.duck.term.android"><img src="./assets/google-play-badge.svg" height="56" alt="在 Google Play 获取 DuckTerm"></a>
</p>

安装后打开 **设置 → Agent 通知 → 扫码配对**，保持这个页面，再回到电脑安装
Hookd。

## 三步完成闭环

1. 在 iOS/iPadOS 或 Android 上安装 **DuckTerm**。
2. 在每台运行编程 Agent 的电脑上安装 **Hookd**。
3. 运行引导式配置，扫描终端里的二维码，再在 App 中点击 **验证**。

```text
编程 Agent + tmux / psmux / Herdr
                  │
                  ▼
            电脑上的 Hookd
          ├── 同网时优先走已认证的 LAN Direct
          ├── 离开局域网后由安全中继承接推送与交互
          └── 本机 Web 控制中心
                  │
                  ▼
      iOS / iPadOS / Android 上的 DuckTerm
```

配对完成后，日常流程会变得很简单：在电脑上开始任务，让 Agent 继续工作；
离开座位后在手机上收到结果或授权请求；需要上下文时展开实时终端，然后直接
回复，不必重新创建另一段对话。

## 它解决了什么

- **Agent 收件箱与通知**：任务完成、失败或需要你时及时出现。
- **手机授权与回复**：上游 Agent 提供相应 Hook 时，可直接批准、拒绝或继续提问。
- **实时终端预览**：在能够安全确认会话与 Pane 身份时，看到对话背后的真实终端。
- **图文输入交接**：把文字和图片送进已适配的 Agent TUI，而不是另起一个手机聊天。
- **多主机连续工作**：Mac、Windows 工作站、Linux 服务器和 WSL 可归入同一个
  DuckTerm 账号。
- **本地控制中心**：默认通过 `http://127.0.0.1:20080` 管理健康状态、集成、
  规则、历史与升级。

## 当前支持范围

| 主机 | 架构 | 后台服务 |
|---|---|---|
| macOS | Apple silicon、Intel | Homebrew services 或 launchd |
| Windows 10 / 11 | x64、arm64 | 隐藏运行的任务计划程序 |
| Linux | x86_64、arm64 | systemd |
| WSL1 / WSL2 | x86_64、arm64 | systemd 或受管理的兼容服务 |

Hookd 当前可识别 12 种编程 Agent 集成：**Claude Code、Codex、OpenCode、
Cursor、Droid、Qoder、Amp、Gemini、Antigravity、Grok Build、Pi 与 Devin**。
长驻终端上下文支持 **tmux、psmux 与 Herdr**。

不同 Agent 对外开放的 Hook 能力并不完全相同。Hookd 只启用上游真实提供的
事件与动作，因此通知、授权、回复和预览能力会随 Agent 及其版本有所差异。

## 安装 Hookd

### macOS — Homebrew（推荐）

```sh
brew install ducksee/tap/duckterm-hookd && \
  "$(brew --prefix duckterm-hookd)/bin/duckterm-hookd" setup --qr
```

Homebrew 同时管理软件包与后台服务。配置向导会发现已安装的 Agent、保留已有的
第三方 Hook、启动 Hookd，并显示配对二维码。以后遇到配置问题，也可以安全地
重新运行这条命令进行修复。

不使用 Homebrew 时，也可以运行下面 Linux/macOS 共用的直接安装脚本。

### Windows 10 / 11 — 原生 PowerShell

请在 PowerShell 5.1 或更新版本中运行：

```powershell
irm https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.ps1 | iex
```

安装器会自动选择 x64 或 arm64、校验 SHA-256、安装内置 Web UI、注册隐藏运行的
后台任务，把 `duckterm-hookd` 与短命令 `dhook` 加入用户 `PATH`，然后开始扫码
配对。PowerShell、psmux、Windows Herdr 与原生 Windows Agent 都应使用这一版。

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

安装器会自动选择 x86_64 或 arm64、校验 SHA-256、安装内置 Web UI、接入检测到
的 Agent，并注册 systemd 服务。

### Windows Subsystem for Linux

请在 **WSL 发行版内部**运行，不要在 PowerShell 中运行：

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

原生 Windows 与 WSL 会被视为两台主机。WSL 安装拥有独立的主机身份、端口、
Agent 集成与服务；有 systemd 时优先使用 systemd，WSL1 则使用可跨 Windows
登录持续运行的受管理兼容服务。

## 验证连接

```sh
duckterm-hookd status
duckterm-hookd test-push --note "Setup verification"
```

`status` 会检查配对、服务归属、云连接、账号成员关系与已发现的 Agent 集成。
已支持的平台也可以使用短命令 `dhook status`。测试推送是异步的，请确认消息最终
出现在 DuckTerm 的 Agent 收件箱中。

以后新安装了编程 Agent，只需重新接入集成，不会改变账号配对或服务状态：

```sh
duckterm-hookd hook install
```

## 高频命令

| 命令 | 作用 |
|---|---|
| `duckterm-hookd setup --qr` | 配对或修复主机、对齐 Agent、启动服务并验证 |
| `duckterm-hookd status [--verbose]` | 查看账号、服务、云、LAN 与集成健康状态 |
| `duckterm-hookd test-push --note "…"` | 发送一条端到端通知测试 |
| `duckterm-hookd hook install` | 重新写入所有已检测 Agent 的 DuckTerm 自有集成 |
| `duckterm-hookd update` | 校验并安装最新版本，保留当前服务归属与配置 |
| `duckterm-hookd ui upgrade` | 只更新独立发版的本地 Web UI |
| `duckterm-hookd firewall status` | 检查 LAN Direct 监听与防火墙状态 |

`upgrade` 与 `update` 完全等价。

## 同网优先，离网可用

手机能够访问电脑时，Hookd 会优先使用经过认证的 LAN Direct；离开这个网络后，
长连接仍可承接通知、授权与回复。本地 Web 控制中心默认只允许本机访问，只有你
显式开启后才会进入局域网模式。

```sh
duckterm-hookd config --lan --reload    # 仅用于可信局域网或 VPN
duckterm-hookd config --local --reload  # 恢复为仅本机访问
```

LAN Direct 默认使用 TCP `11434`。不要通过公网路由器转发这个端口或 Web 控制
中心端口。在 Windows 或启用了严格防火墙的 Linux 上，先查看精确规则与监听结果：

```sh
duckterm-hookd firewall status
```

## 隐私与共存

- Agent 进程、代码仓库与终端会话始终留在你的电脑上。
- 配对凭据与本地设置保存在 `~/.duckterm`；平台支持时会使用私有文件权限。
- Hookd 会标记自己拥有的每一条集成。重复配置和卸载不会破坏 Claude、Codex
  或其他工具已有的第三方 Hook。
- 实时预览与交互输入要求能够确认 Agent 会话和终端目标；证据不足时会停止输入，
  而不是猜测一个 Pane。
- 本地 Web UI 默认只监听 `127.0.0.1:20080`。

## 升级与卸载

所有官方 Homebrew、Windows、Linux 与 WSL 安装都可以使用同一条升级命令：

```sh
duckterm-hookd update
```

卸载时请明确选择范围：

```sh
duckterm-hookd hook uninstall             # 只移除 DuckTerm 自有 Agent Hook
duckterm-hookd unpair --yes               # 解除账号/主机配对，保留本地数据
duckterm-hookd service uninstall --yes    # 移除 Hook、后台服务和原生运行时
duckterm-hookd service uninstall --purge --yes  # 同时删除 Hookd 本地数据
```

如果软件包由 Homebrew 管理，并且也希望移除包文件，请在服务清理后执行
`brew uninstall duckterm-hookd`。

<details>
<summary><strong>发布包与手动校验</strong></summary>

| 文件 | 平台 |
|---|---|
| `duckterm-hookd_darwin-arm64.tar.gz` | macOS Apple silicon |
| `duckterm-hookd_darwin-amd64.tar.gz` | macOS Intel |
| `duckterm-hookd_windows-amd64.zip` | Windows x64 |
| `duckterm-hookd_windows-arm64.zip` | Windows arm64 |
| `duckterm-hookd_linux-amd64.tar.gz` | Linux x86_64 |
| `duckterm-hookd_linux-arm64.tar.gz` | Linux arm64 |
| `duckterm-hookd_linux-amd64-wsl.tar.gz` | WSL x86_64 |
| `duckterm-hookd_linux-arm64-wsl.tar.gz` | WSL arm64 |

手动下载时，请使用每个 Release 附带的 `SHA256SUMS` 校验文件。

</details>

官方发布包是专有软件；许可证见每个安装包内的 `LICENSE`。
