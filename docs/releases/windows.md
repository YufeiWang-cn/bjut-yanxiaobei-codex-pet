# BJUT 燕小北 · Windows 独立增强版

当前源码 **0.2.5**。第一次安装请先双击本包根目录 **START-HERE.html**；它会用浏览器打开逐步说明，无需开发工具。也可查看 docs/BEGINNER.md。版本号见 VERSION.txt。

一个带额度气泡和任务活动面板的独立桌宠。无需安装原生素材版；需要 Windows、已登录的 Codex 桌面客户端和 Node.js。

当前版本 0.2.5 修复部分电脑任务始终空闲，兼容更多日志目录和会话来源，并在日志缺失时从最近本机会话发现正在运行的顶层 Codex 任务。任务活动只跟踪 Codex，普通 ChatGPT 聊天不读取、不展示；任务行保留 `Codex` 来源标识。更新检查、审批识别和卸载功能继续保留。卸载先关闭桌宠，再运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\windows-companion\Uninstall.ps1 -Confirm:$false`，最后删除解压文件夹。详见 docs/INSTALL.md。

## 快速开始

1. 安装 Node.js 22 或更新版本并启用 PATH（测试使用 24.19.0）。
2. 完整解压本包；保留 `windows-companion` 内所有文件。
3. 双击 `windows-companion/Start.vbs`。默认入口不会留下终端窗口。
4. 首次启动后默认开启跟随 Codex 启动；右键可关闭或重新开启，也能分别隐藏额度气泡 / 任务队列、打开“使用说明”或关闭桌宠。

启动错误可用 `Start-Debug.cmd` 查看。它是调试入口，会故意保留终端。默认启动器使用 Windows PowerShell 5.1；PowerShell 7 手动入口、禁用 VBScript 的设备、更新及卸载见 `docs/INSTALL.md`。

双击燕小北恢复已有 Codex 窗口；点击具体活动跳到对应任务。“重置 ×N”只是次数显示，不会消耗重置。数据由本机 app-server 和日志提供，客户端更新可能影响兼容性，数据以官方客户端为准。

界面效果见 `docs/images/hero.png`（示例数据）。

新安装首次启动会注册当前用户的 Windows 跟随观察器；右键可关闭或重新开启，手动关闭后不会被下次启动重置。移动目录或卸载前先关闭该选项。

完整使用说明见 `docs/INSTALL.md`，排错见 `docs/FAQ.md`，隐私见 `docs/PRIVACY.md`。本包不含开发测试和原生图集；开发请使用完整源码仓库。

个人制作，非官方产品。代码许可见 `LICENSE.md`；角色图片不适用 MIT，使用限制见 `docs/FAQ.md`。
