# BJUT 燕小北 · Codex 原生素材版

当前源码 **0.2.2**。第一次安装请先双击本包根目录 **START-HERE.html**；它会用浏览器打开逐步说明，无需开发工具。也可查看 docs/BEGINNER.md。版本号见 VERSION.txt。

这是个人制作、由 Codex 桌宠宿主加载的 v2 素材包，不包含独立额度窗口，也不是官方出品。

## 安装

1. 完整解压。
2. 把 `codex-native/bjut-yanxiaobei` 文件夹复制到 `%USERPROFILE%\.codex\pets\`。使用自定义 `CODEX_HOME` 时放在其 `pets` 目录下。
3. 在支持自定义 v2 桌宠的客户端中打开设置 → Pets → Refresh，选择 BJUT 燕小北，并唤醒桌宠。

也可在解压目录打开 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-CodexPet.ps1
```

已有同名版本时，脚本默认拒绝覆盖；加 `-Force` 会先备份再更新。其他系统的兼容性、安装与卸载见 `docs/INSTALL.md`。

需要五小时 / 每周额度、任务活动和独立窗口，请按操作系统下载 Windows 或 macOS 独立增强版；本包不需要 Node.js。

Mac 原生素材安装：手动复制到 `~/.codex/pets/`，需支持同一 v2 格式的宿主；本包未做 Mac 实机验证。另有 0.2.0 新增的 macOS Electron 增强版源码包，详见 docs/MACOS.md；Windows 程序仍不能直接在 Mac 运行。

代码许可见 `LICENSE.md`；角色图片不适用 MIT，使用限制见 `docs/FAQ.md`。
