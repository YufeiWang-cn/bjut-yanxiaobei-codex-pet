# BJUT 燕小北 · macOS 增强版源码包

当前源码 **0.2.6**。第一次安装请先双击本包根目录 **START-HERE.html**；它会用浏览器打开逐步说明，无需开发工具。也可查看 docs/BEGINNER.md。版本号见 VERSION.txt。

0.2.6，个人制作，非官方产品。优先读取 Codex App Server 运行时状态并增强新环境路径兼容；任务活动只跟踪 Codex，普通 ChatGPT 聊天不读取、不展示，折叠任务面板保留 `Codex` 来源标识；短暂自动审批保持进行中，明确排除子任务。无论是否开启跟随显示，观察到 Codex 退出后桌宠都会退出。

右键菜单可打开离线“使用说明”、主动检查更新；启动也会检查 GitHub Release，失败时会静默重试一次。新安装默认跟随 Codex 显示，首次运行打包 .app 时尝试设置登录项；源码包不能直接登录自启，未签名 .app 是否成功仍需系统验证。更新查询跟随系统代理，只打开发布页，不自动覆盖源码。为避免误触，卸载不放入桌宠菜单；请双击发布包根目录的 `Uninstall.command`，可选择保留或清除数据。

要求 macOS 13+；本包是源码，不是签名/公证的 DMG 或现成 .app。代码与跨平台界面已测试，Mac 实机待验收。

1. 安装 Node.js 22.12+，完整解压。
2. 终端进入 macos-companion，依次运行 npm ci、npm run prepare-assets、npm test。
3. Apple Silicon 运行 npm run pack:arm64，Intel 运行 npm run pack:x64。
4. 将 dist 中的完整 BJUT YanXiaoBei.app 复制到应用程序目录，之后双击，无需常驻终端。
5. 连接失败可从右键选择 Codex 应用和 CLI；不要上传登录文件。

源码试用可 npm start（前台终端）或装好依赖后运行 Start.command（后台）；纯演示 npm run demo 不连接账号。

签名限制、首次连接、右键操作、登录项、更新和卸载见 docs/MACOS.md；隐私见 docs/PRIVACY.md。重置次数只显示，不兑换。代码许可见 LICENSE.md；角色图片不适用 MIT，使用限制见 docs/FAQ.md。
