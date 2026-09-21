# macOS 安装与使用

[返回首页](../README.md) · [常见问题](FAQ.md) · [隐私](PRIVACY.md)

当前源码 0.2.4。不熟悉终端的人先看 [零基础安装步骤](BEGINNER.md) 的 C 部分：含打开终端、拖入文件夹、逐条命令和成功标志。也可双击包内 START-HERE.html。下面的架构/签名内容保留作进阶参考。

## 版本与验证边界

0.2.0 新增个人制作的 Electron Mac 增强版：独立桌宠、5H/7D 额度、可重置次数、折叠任务、状态动作、任务跳转和菜单栏入口。不依赖原生桌宠。

本次开发环境是 Windows。共享逻辑、资源和实际 Electron 界面已经测试，**Mac 实机、签名/公证、系统通知与登录项尚未验收**。`bjut-yanxiaobei-macos.zip` 是源码运行/构建包，不是现成 DMG 或签名安装器。

## 1. 运行条件

- **macOS 13 Ventura 或更新版本**。Electron 44 不再支持 macOS 12，见 [官方说明](https://www.electronjs.org/docs/latest/breaking-changes/#removed-macos-12-support)。
- Apple Silicon（M 系列）选 arm64，Intel 选 x64。在“关于本机”检查芯片；Rosetta 终端的 `uname -m` 可能显示兼容架构，不宜只凭它判断。
- 已安装、已登录且能正常工作的 Codex，以及支持 `app-server --stdio` 的本机 CLI。内部安装路径可能随客户端版本改变。
- 源码安装/构建需 [Node.js 22.12+ 和 npm](https://nodejs.org/en/download)，首次需要访问 npm 官方仓库和 Electron 下载服务。
- 完整构建出的 `.app` 自带 Electron，日常运行无需系统 Node.js、PowerShell、Python 或终端。

不提供账号，也不要求向项目填写 API Key。Windows 的 VBS / PowerShell / WPF 入口不能直接用于 Mac。

## 2. 完整解压与安装依赖

解压到长期保留的目录。终端输入 `cd `（带空格），将内层 `macos-companion` 文件夹拖入终端，回车：

```sh
node --version
npm --version
npm ci
npm run prepare-assets
npm test
```

`npm ci` 根据锁文件安装固定版本；下载体积较大，取决于网络。不要删除锁文件解决下载问题，也不要执行不明镜像脚本。项目自带 HTTPS npm 源配置。

资源同步会复用 57 张原图、动画时序、数据桥和许可。独立 Mac 下载包已带齐这些资源，无需另外下载原生版或 Windows 版。

## 3. 推荐：构建 .app，日常双击启动

仍在上述目录：

```sh
# Apple Silicon 选择这一条
npm run pack:arm64

# Intel 选择下面这一条；不需要两条都运行
# npm run pack:x64
```

在生成的 `dist` 子目录中找到 **BJUT YanXiaoBei.app**，复制完整应用到 `~/Applications`（用户应用程序目录，没有可在 Finder 创建），或有写权限的 `/Applications`。双击后可以关闭构建终端。

只复制整个 `.app`，不要拆分内部 Electron、runtime 或资源文件。若需生成 DMG/ZIP，在 Mac 上运行 `npm run dist:arm64` 或 `npm run dist:x64`。

### 签名与系统安全

默认构建**未做 Developer ID 签名和 Apple 公证，不自动发布**。自己构建不等于具备可信分发签名。系统拦截下载的未签名应用时，先核验来源、版本和校验值，优先从审阅过的源码本机构建，或等待经签名验证的发布包。

不要全局关闭 Gatekeeper，不要执行批量删除隔离属性的命令。可靠的公开二进制需要发布者在 Mac 上配置证书、公证并实机验收，默认 `identity: null` 需替换为正式配置；仓库不含证书、密钥或账号。

## 4. 不打包时的源码入口

```sh
# 前台真实连接：关闭终端可能使它退出
npm start

# 纯演示，不读取真实账号、不打开真实任务、不改自启动
npm run demo

# 安装依赖后，脱离终端后台运行
chmod +x Start.command
./Start.command
```

`Start.command` 显示启动提示后可关闭终端。Finder 双击它会短暂打开终端；**完全不出现终端请使用 .app**。它不会自动安装依赖或修改系统安全策略。启动日志写入本地数据目录的 `launcher.log`。

已有旧版运行时先从菜单栏退出。程序有单实例保护，不会每双击一次多开一只。

## 5. 首次连接与配置路径

先确认 Codex 登录有效并能执行任务。连接失败时：

1. 右键 / 菜单栏 → **选择 Codex 应用…**，选择实际使用的 `Codex.app` 或兼容宿主应用包。
2. **选择 Codex CLI…**，选能执行 app-server 的文件；不能选整个 .app、Windows EXE 或陌生脚本。
3. 如果终端能运行 codex，用 `command -v codex` 查看位置；在文件选择器中用“前往文件夹”输入所在目录。
4. 选择路径后会重新连接，也可手动选择 **重新连接数据桥**。

Finder 启动不会完整继承终端 PATH，程序会尝试常见 Homebrew / 用户 CLI 目录。不同客户端内部路径不保证自动识别。

高级配置在以下文件，**退出桌宠后再编辑并先备份**：

`~/Library/Application Support/BJUT-YanXiaoBei/mac-settings.json`

```json
{
  "quotaVisible": true,
  "tasksVisible": false,
  "followCodex": true,
  "launchAtLogin": true,
  "notify": false,
  "codexApp": "/Applications/Codex.app",
  "codexExecutable": "/opt/homebrew/bin/codex",
  "codexHome": "/Users/your-name/.codex",
  "logRoot": "/Users/your-name/Library/Logs/Codex"
}
```

示例路径不是对你电脑安装位置的保证，替换为核实过的真实路径。`codexHome` / `logRoot` 可留空走默认探测。配置中不展开 `~`，请填完整绝对路径。

环境变量对应为 `CODEX_APP_PATH`、`CODEX_EXE`、`CODEX_HOME`、`CODEX_LOG_DIR`；非空设置项优先。用 `YANXIAOBEI_DATA_DIR` 可改数据目录，不要指向公开仓库。

本项目不要求屏幕录制、辅助功能或全盘访问权限，不控制 Codex 页面。必要目录读取遭拒时只为必要位置处理权限，不要关闭全局安全功能。

## 6. 日常操作

| 操作 | 行为与限制 |
| --- | --- |
| 拖动角色或两块面板顶部 | 限制到显示器工作区；显示器移除/尺寸变化时重新校正 |
| 双击角色 | 激活已有 Codex 应用，不发送首页/新任务链接；多窗口前台选择由 macOS 决定 |
| 点击任务行 | 打开 codex 任务协议；需客户端支持，且该任务本机可访问 |
| 任务摘要 / 收起箭头 | 展开/收回任务；它可以与额度气泡分别隐藏 |
| 额度 × | 只隐藏额度气泡 |
| 右键 / 菜单栏 | 显隐、刷新、清除提醒、路径配置、重连、退出 |
| 显示桌宠 / 找回位置 | 显示并把窗口限制回可见工作区 |
| 系统完成通知 | 默认关闭，主动开启后受系统通知权限控制；拒绝仍有桌宠文字/面板提醒 |
| 关闭桌宠 | 退出本项目窗口和数据桥，不关闭 Codex |

逻辑尺寸：纯桌宠 132×182、额度 410×190、仅任务 410×256、两面板 410×374。长标题截断，悬停查看；任务可滚动。工作区过小可能需调高显示分辨率。

窗口置顶、全屏与多桌面行为受 macOS 限制，不保证覆盖所有全屏应用。菜单栏可找回，Dock 不常驻额外图标。

## 7. 自启动的两个不同开关

- **跟随 Codex 显示/隐藏**：新安装默认开启；仅在桌宠已运行时，每 2 秒观察所选应用；Codex 退出则隐藏、运行则显示，菜单栏仍保留。取消勾选后桌宠会立即重新显示。它不帮你启动 Codex。完全关闭桌宠后不会自行复活。
- **登录时启动**：新安装的打包 .app 首次运行会尝试启用，菜单可再关闭或重开；源码/演示禁用。先将 .app 放在固定位置。现代 macOS 登录项 API 对签名/公证有要求，未签名包不能保证可用，见 [Electron app 文档](https://www.electronjs.org/docs/latest/api/app#appsetloginitemsettingssettings-macos-windows)。
- 个人未签名构建可由你在系统“登录项”手动添加可信的已安装 .app，再退出登录验证。菜单勾选不等于验收通过。
- 想登录后等待 Codex 再显示，需要两项都有效；现有用户的已保存选择会保留。源码包不是可直接登录自启的 .app。
- 移动、升级或卸载前先关闭登录项；不要把源码调试入口加入登录项。

## 8. 数据和状态边界

两种增强版共用逐轮状态逻辑，完成、中止、旧轮迟到、等待审批和提醒过期走同一规则。活动心跳超过 15 秒未更新则显示离线，不继续伪装思考；恢复连接后再同步。减少动态效果只停帧动画，不改文字状态。

Mac 优先识别桌面日志，还会从 app-server 返回的近期本机根任务发现会话记录。无日志降级主要保障开始/结束/中止，审批、错误、远程任务或本地文件缺失可能不完整。列表不等于 Codex 侧栏总数。

额度变动通知到达后立即更新；运行中的任务最多每 20 秒、空闲时最多每 60 秒查询一次，任务结束后还会合并补查一次。元数据每 20 秒、状态每秒检查；手动刷新会立即提示进度，失败保留上次额度并显示错误/时间，不代表更新成功。重置未知为 `--`，明确零次为 `×0`；绝不兑换。

## 9. 更新、卸载与排错

更新：关闭桌宠和登录项，保留旧版便于回退；完整解压新版，重新安装依赖、测试、打包，替换自己的 .app，再设置登录项。不要只覆盖单个脚本或帧图。

更新检查：启动时检查 GitHub Release，右键菜单可以主动检查。先读取 GitHub 发布订阅，失败才回退 REST API，避免共享代理出口用尽匿名 API 配额后误报。查询使用 Electron 的系统网络接口，跟随 macOS 系统代理/PAC；未配置代理时直连。只有浏览器扩展启用代理而系统未配置时，应用无法借用浏览器扩展。查询约 5 秒截止；对新版本可打开网页、忽略该版本或仅暂时忽略，不自动安装。卸载：优先右键 →“卸载并清除本地数据…”（会关闭登录项，清除 `~/Library/Application Support/BJUT-YanXiaoBei`，并退出），再将 .app / 源码目录移入废纸篓。或先关闭登录项并退出，再运行包内 `Uninstall.command` 清理配置。**不需要删除 .codex、Codex 的登录或任务。**

| 问题 | 检查 |
| --- | --- |
| 找不到 node/npm | Node 是否安装、版本与 PATH；重新开终端 |
| 下载失败 | 网络、HTTPS 下载源、磁盘空间；保留锁文件 |
| 无法启动 | macOS ≥13、架构匹配、完整复制 .app、系统安全提示 |
| 连接失败 | 登录、CLI 路径、app-server 支持；菜单重新连接 |
| 任务跳转失败 | codex 协议注册、客户端版本、任务是否本机可访问 |
| 桌宠不见 | 菜单栏找回；跟随显示是否隐藏了窗口 |
| 仍有终端 | npm start 是前台；日常改用 .app 或后台启动器 |
| 通知/自启动无效 | 系统权限、签名、安装位置；必须实际验证 |

反馈提供系统、芯片、Codex 版本、复现步骤和脱敏错误，不要上传原始会话、任务缓存、私人路径或令牌。开发检查方法见 [首页](../README.md) 的“开发与发布”部分；Mac 实机验收仍待完成。
