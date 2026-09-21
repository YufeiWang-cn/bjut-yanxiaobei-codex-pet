# BJUT 燕小北 · macOS 增强版

当前源码 0.2.4。零基础用户先看 [分步安装指南](../docs/BEGINNER.md)，或双击包根目录 START-HERE.html。旧 .app 需重新构建才能更新。新安装默认跟随 Codex 显示；打包 .app 首次运行尝试登录启动（系统可能要求授权），源码运行不会设置登录项。右键可关闭跟随、打开“使用说明”、检查更新或卸载并清除本地数据；解压包也包含 Uninstall.command。

个人制作，非官方产品。独立桌宠、额度、重置次数、折叠任务和状态动作。

要求 macOS 13+；当前为实验性源码版，跨平台逻辑与界面已测试，Mac 实机与签名/公证待验收。

在本目录执行：

```sh
npm ci
npm run prepare-assets
npm test
npm run pack:arm64
# Intel 改为 npm run pack:x64
```

把 dist 中的完整 BJUT YanXiaoBei.app 复制到应用程序目录，之后双击，不需常驻终端。未签名分发限制请先阅读指南。

源码前台运行 `npm start`；离线演示 `npm run demo`；装好依赖后可 `chmod +x Start.command` 再运行启动器、关闭终端。

连接失败从右键选择 Codex 应用和 CLI。“重置 ×N”只是显示，不兑换。

[完整使用指南](../docs/MACOS.md) · [隐私](../docs/PRIVACY.md) · [代码许可](assets/LICENSE.md) · [常见问题与角色使用限制](../docs/FAQ.md)

维护时 runtime/assets 从 windows-companion 规范源同步，不单独修改副本。独立 Mac 包已携带所需资源。
