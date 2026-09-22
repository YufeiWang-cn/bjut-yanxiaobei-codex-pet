# 安装与使用

[返回首页](../README.md)

第一次安装请先看 [零基础安装步骤](BEGINNER.md)，或双击解压根目录的 START-HERE.html。下面是补充细节，不要求普通用户先理解 PATH、CLI 或 PowerShell。

## 先选版本

本项目为个人制作。只想换 Codex 自带桌宠外观：选原生素材版；要同时看额度和任务，按系统选 Windows 或 macOS 增强版。三种版本互不依赖，不需要都安装。

Mac 的环境准备、Apple Silicon / Intel 构建、无终端 .app、路径、自启动、卸载和安全限制见 [Mac 完整指南](MACOS.md)。当前为实验性源码版，Mac 实机待验收；以下 PowerShell / VBS 命令仅用于 Windows。

## 原生素材版

### 手动安装

默认目录结构：

```text
Windows: %USERPROFILE%\.codex\pets\bjut-yanxiaobei\
macOS:   ~/.codex/pets/bjut-yanxiaobei/

bjut-yanxiaobei/
├── pet.json
└── spritesheet.webp
```

如果设置了 `CODEX_HOME`，改用它下面的 `pets/bjut-yanxiaobei/`。复制的是内层素材文件夹，不是整个仓库；不要额外套一层同名目录。

本仓库在 Windows 验证了素材格式和安装脚本。macOS 的路径说明仅适用于支持同一 v2 本地宠物格式的客户端，未在本次发布中实机验证。

复制后在支持该功能的桌面客户端里打开设置中的 Pets，刷新列表并选择 BJUT 燕小北；用 `/pet` 或对应菜单唤醒 / 隐藏。菜单名称可能随客户端版本变化。[官方桌宠说明](https://learn.chatgpt.com/docs/pets)

本包包含透明 WebP 图集，规格为 1536 × 2288、8 × 11、`spriteVersionNumber: 2`。不要裁成别的尺寸再安装，也不要直接把它当作网页自定义宠物上传包。

### Windows 安装脚本（完整仓库包）

在仓库根目录打开 PowerShell：

```powershell
# 首次安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexPet.ps1

# 已有同名版本：先备份再覆盖两个素材文件
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexPet.ps1 -Force

# 只查看将要执行的操作
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexPet.ps1 -WhatIf
```

可通过 `-CodexHome '你的 Codex 数据目录'` 指定目录。脚本不修改客户端程序或其他桌宠。

### 卸载

先在客户端里切换到其他宠物或隐藏桌宠，再运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Uninstall-CodexPet.ps1 -Confirm:$false` 并刷新列表。加 `-RemoveBackups` 可一并删除本项目安装器产生的备份；加 `-WhatIf` 可先预览。不会删除 Codex 自己的偏好、账号或其他宠物。

## Windows 独立增强版

### 运行条件

- Windows 桌面环境，支持 WPF；Windows 10 / 11 为预期目标，具体版本应自行验证。
- 已安装、已登录且可正常工作的 Codex 桌面客户端。
- [Node.js](https://nodejs.org/en/download) 22 或更新版本，包含在 PATH 中；测试使用 Node.js 24.19.0。
- Windows PowerShell 5.1（默认启动器使用它），或 PowerShell 7 手动启动。
- 可用的 Codex 可执行文件。程序优先寻找桌面客户端的本地 CLI，也支持环境变量 `CODEX_EXE` 或 PATH 中的 `codex`。

不捆绑 Node.js、Codex、账号或访问令牌。没有第三方 npm 包，不需要运行 `npm install`。

### 安装与启动

1. 解压完整项目或 Windows 版发布包到长期保留的目录，例如你自己的应用文件夹。
2. 在 Codex 中登录并确认能执行任务。若运行旧私人版燕小北，先右键关闭旧版；两者使用同一个单实例锁，避免重复运行。
3. 进入 `windows-companion`，双击 `Start.vbs`。它以隐藏方式启动 PowerShell，不应留下终端窗口。
4. 若连接失败，查看提示；用 `Start-Debug.cmd` 启动会保留调试窗口，便于阅读错误。**只有调试入口会故意留下终端。**

任务活动面板会在每一行显示 `Codex`，只表示本机 Codex 任务；普通 ChatGPT 聊天不读取、不展示。没有 Codex 活动时显示空闲。0.2.5 起，即使常用桌面日志缺失，也会从最近本机会话中寻找正在运行的顶层 Codex 任务。

若设备禁用了 Windows Script Host / VBScript，可在你自己打开的 PowerShell 中运行（终端关闭会影响这种手动启动方式）：

```powershell
# 位于仓库根目录
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\windows-companion\Launch.ps1

# 已安装 PowerShell 7 时
pwsh -NoProfile -ExecutionPolicy Bypass -STA -File .\windows-companion\Launch.ps1
```

执行策略参数只用于本次进程，不修改系统永久策略。受组织策略限制时应按管理员要求操作，不建议为了桌宠关闭系统安全功能。

### 跟随启动：新安装首次启动默认开启

仅下载或解压 ZIP 不会执行任何程序。新用户第一次双击 `Start.vbs` 并成功找到 Node.js 后，桌宠会为当前用户创建 Windows 登录启动项；下次登录时运行轻量观察器，看到 Codex 桌面窗口才启动燕小北。不是让桌宠代你启动 Codex，也不修改 Codex 客户端文件。已有本地设置的老用户不会被强制重新开启。

右键桌宠 → 取消勾选“跟随 Codex 启动”即可关闭，登录启动项与观察器会停止；再次勾选可恢复。手动关闭桌宠后，观察器不会立刻把它重新打开；下一次检测到新一轮 Codex 启动才会触发。右键“使用说明”可随时打开随包附带的离线指南。

也可从仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-companion\Configure-Autostart.ps1 -Enable
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-companion\Configure-Autostart.ps1 -Disable
```

启用后不要随意移动文件夹。需要移动时先关闭跟随启动，移动后从新位置启动并重新启用。默认启动项名称为 `BJUT-YanXiaoBei-Codex.lnk`。原有私人版的启动项不会被本项目删除；迁移时请自行停用旧版，避免旧路径重新启动旧程序。

### 数据位置与更新

默认运行数据写入 `%LOCALAPPDATA%\BJUT-YanXiaoBei\`：

| 文件 | 用途 |
| --- | --- |
| `bridge-state.json` | 额度及任务状态缓存，可能含任务标题 / ID |
| `badge-position.json` | 桌宠位置 |
| `ui-settings.json` | 气泡与任务面板显示偏好 |
| `autostart-enabled.flag` | 是否主动开启跟随启动 |
| `autostart-configured.flag` | 记住已做过跟随开关选择，避免关闭后被下次启动重置 |
| `update-preferences.json` | 被忽略的 GitHub Release 版本号 |

更新前关闭桌宠和跟随启动，完整解压新版本，启动后重新开启跟随启动。用户数据不放在仓库内，通常能保留位置和偏好。旧私人版的偏好不会自动迁移。

增强版每次启动会联网检查 GitHub Release；右键燕小北 →“检查更新”可主动检查，点击后立即显示检查提示。先读取 GitHub 发布订阅，订阅不可用才尝试可能限流的 REST API，无需 GitHub 令牌。Windows 查询使用系统代理/PAC，也支持启动时的 `HTTPS_PROXY` 环境变量；未开代理时尝试直连。代理若只设置在浏览器扩展中，请在代理软件里开启“系统代理”。Mac 版使用系统代理。Mac 查询约 5 秒、Windows 连同代理检测约 7.5 秒截止。发现更高版本后优先展示发布说明里的“新增 / 修复 / 优化”等条目；Windows 的长说明可换行、滚动阅读。可选择“前往更新”打开发布页自行下载、“忽略此版本”直到下一个新版本，或“暂时忽略”到下次启动。GitHub 暂时不可达时，手动检查可选择打开发布页；失败不影响启动，不会自动安装。若作者尚未在 GitHub 创建并填写新版 Release，本地改动不会凭空出现在更新提示中。原生素材版无法修改 Codex 宿主的右键菜单。

可选环境变量：`NODE_EXE` 指定 Node 可执行文件，`CODEX_EXE` 指定 Codex 可执行文件，`CODEX_HOME` 指定 Codex 数据目录，`YANXIAOBEI_DATA_DIR` 指定助手运行数据目录。平时不需要设置。

### 卸载

1. 右键 → 关闭桌宠。
2. 在解压根目录运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-companion\Uninstall.ps1 -Confirm:$false`；可先加 `-WhatIf` 预览。脚本清除本项目的启动项与 `%LOCALAPPDATA%\BJUT-YanXiaoBei` 内的设置、缓存和更新忽略记录。
3. 删除解压的项目目录。如还安装了原生素材版，请按上面的原生卸载步骤另行移除。

以上操作不需要删除 `.codex` 目录，不应触碰其中的登录信息、任务或其他宠物。
