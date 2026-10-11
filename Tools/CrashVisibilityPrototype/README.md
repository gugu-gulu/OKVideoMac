# Crash Visibility Prototype — G0

这是独立 macOS 原型，不是正式 OKVideoMac 功能。正式 App 仍为 **0.8.4 / Build 137**。
没有修改播放器、正式工程、Sparkle、签名/公证/DMG 发布脚本或商业目录，也不替换桌面 App。

当前原型为 **0.1.2 / Build 3**。第 3 步已完成上传进程异常路径和单窗口恢复界面的本地验收，
结果见 [PHASE3-ACCEPTANCE.md](PHASE3-ACCEPTANCE.md)。预启动 AppKit 模态窗口交给 SwiftUI 的视觉验收失败，
已移除该交接；当前由同一个 SwiftUI 窗口显示恢复提示和测试界面，业务初始化仍等待用户决定。
新的单窗口切换已由用户实测通过：布局正常，无需 Dock；⌘Q 退出、恢复页红色关闭、开启和关闭授权也已通过人工操作与本地证据核对。
撤回后正常重启及新 C 崩溃重启的程序化复核通过：授权保持关闭，新报告只在本机保存。

0.1.0 / 0.1.1 的 Swift/C 及 App.init 报告曾在真实 Sentry 后台验证版本、源码行及调用栈分组。
历史验收见 [ACCEPTANCE.md](ACCEPTANCE.md)、[PHASE1-2-ACCEPTANCE.md](PHASE1-2-ACCEPTANCE.md)，
启动分析见 [STARTUP-ANALYSIS.md](STARTUP-ANALYSIS.md)。当前 0.1.2 的真实 Swift/C 事件、版本、UUID 与源码行也已复验通过，
详见 [PHASE4-ACCEPTANCE.md](PHASE4-ACCEPTANCE.md)。固定产物、同条件泄漏及 CLI 临时对象对照已完成；
不接入正式 App，也不替换桌面 App。

## 本原型验证什么

```text
独立入口 → 私有目录及单实例锁 → 处理上一份原始报告 → 安装 PLCrashReporter
       → SwiftUI App.main() / 单窗口恢复提示 → 用户继续 → 模拟业务 bootstrap
下次启动 → PLCrashReport 公共模型 → 白名单 CrashRecord
       → 用户授权且有私有配置 → Sentry 公共 SDK → 私有项目
```

- 捕获安装在 `PrototypeEntry.main()`，早于 SwiftUI App.main() 和模拟业务初始化，不依赖 onAppear/task。
- PLCrashReporter 是唯一安装的第三方崩溃捕获器。系统 CrashReporter 保持原状。
- Sentry 仅在已授权、已配置且有待发报告时，在独立上传子进程启动。禁用其 crash handler、自动会话、MetricKit、hang、性能、profiling、日志、metrics、网络采集、breadcrumbs 与 swizzling。macOS SDK 不启用 Replay。
- 只用 Sentry 的公共事件模型与传输；没有自行拼装或上传 Envelope。
- 撤回授权：先关闭授权，再终止并等待本次 SDK 上传子进程退出，最后清理待发文件及 SDK 缓存。已经抵达服务器的数据无法撤回。
- 回包 2xx 才清除对应待发记录；失败由本地白名单队列保留，后续启动/手动重试。重试沿用 event ID，不声称网络“恰好一次”。
- SDK 自己的磁盘队列在上传子进程退出后及下次启动时清理，不让它绕过授权自主回放。管道读写及等待发生在后台，8 秒截止时间在启动子进程及写管道之前建立；输出有大小限制。父进程退出后，子进程通过 EOF 或父进程存活检查结束。SDK `close()` 会异步 flush，因此不能先让它使用的 URLSession 失效；本原型用进程退出收束其后台队列，不修改 SDK。
- “继续打开原型”只确认已见过哪些报告，不会授予上传权限或删除报告。普通重启不重复拦截；新崩溃会重新提示。
- 不为诊断失败删除用户配置或自动重启。原型捕获初始化失败时，模拟业务入口仍能继续。

## 代码边界

| 模块 | 责任 |
| --- | --- |
| `Sources/CrashVisibilityApp/Entry.swift` | 最早入口、独立 CLI 故障注入；保持 reporter 存活 |
| `Sources/CrashVisibilityApp/PrototypeApp.swift` | 保留早期独立 UI 实验入口；不是当前启动演练 |
| `RecoveryShellApp` / `StartupRehearsal` | 捕获先安装；同一个 SwiftUI 窗口内恢复提示 → 延迟模拟业务；正式租约原样投影 |
| `OKCrashManager` | PLCrashReporter 安装、上次报告恢复 |
| `CrashRecord` / `CrashMapper` | 使用 PLCrashReport 公共模型读取；重建白名单，不上传原始报告 |
| `ReportStore` | 私有目录、单实例锁、授权、有界报告存储 |
| `RecoveryCoordinator` | 恢复页状态、提示确认与授权分离、继续启动仅执行一次 |
| `SentryAdapter` | 主进程管理授权、上传子进程、HTTP 回执、取消及缓存清理 |
| `UploadProcess` | 后台有界管道 I/O、截止时间、撤回取消、等待子进程退出 |
| `SentryUploadWorker` | 单次官方 SDK 发送；不安装崩溃捕获器、不解析原始报告、不自行拼装 Envelope |
| `HandlerProbe` | 只读检查 Signal/Mach/NSException handler，保持 Mach send rights 到比较结束 |
| `Fixture/CrashFixture.c` | 独立优化 C dylib 的 PROT_NONE 测试故障；不涉及播放器 |
| `Scripts/` | 原型专用构建、校验、测试和可选符号上传 |

默认数据目录是 `~/Library/Application Support/com.okvideomac.CrashVisibilityPrototype`，
不是 OKVideoMac 的目录。自动测试均改用 `build/` 下的临时目录。

原始报告仅在本机临时保存，解析后清除；PLCrashReporter 单份上限 1 MiB。
过滤后的报告最多保留 3 份、7 天，过期检查在启动/访问队列时执行。
没有运行的 App 无法在日历时间到期时主动清理文件。目录 0700，报告和授权文件 0600。

事件白名单：原崩溃版本/Build、崩溃时间、系统版本、CPU 架构、线程编号/崩溃标志、
调用地址、模块 UUID/加载地址/大小、必要信号代码；另含稳定 event ID、固定原型标识及由自有模块判断的 in_app 布尔标记。
异常与崩溃线程引用同一组白名单堆栈，保证 Sentry 按堆栈分组，而非仅按信号和错误代码聚合。
不采集硬件型号、设备 ID、用户、用户名路径、寄存器值、任意异常文案、视频内容、URL、
配置、历史、Cookie、Token、日志、请求、截图或内存转储。
原型外的模块名称替换为 UUID 占位名。自己的 image_vmaddr 从构建清单随原始报告保存，
恢复时不拿新版本模块地址替代旧版本。`beforeSend` 重建事件，集成测试再检查实际 SDK 出站数据。

## 构建及本地验证

要求：Apple Silicon、macOS 12+、Xcode/Swift 6 工具链、Python 3、现有 Developer ID Application 签名身份。
本轮验证机为 macOS 14.8.9 / arm64、Xcode 16.2 / Swift 6.0.3。

```sh
cd Tools/CrashVisibilityPrototype
CVP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' Scripts/build-release.sh
swift test -c release -Xswiftc -g
python3 Scripts/test-integration.py
python3 Scripts/test-startup-rehearsal.py
python3 Scripts/test-upload-process.py
python3 Scripts/test-recovery-shell.py
python3 Scripts/upload-symbols.py --check-only
open -n build/CrashVisibilityPrototype.app --args --startup-rehearsal --recovery-shell-ui \
  --state-root /absolute/isolated/test/state
```

依赖固定为 PLCrashReporter **1.12.2**（commit `0254f941c646b1ed17b243654723d0f071e990d0`）及
Sentry Cocoa **9.30.1**（`Package.resolved`）。PLCrashReporter 使用其原有 Xcode 静态框架 target，
没有修改上游源码。原因是当前 SwiftPM 为 C/C++ 源文件注入了不可编译的 Objective-C 资源头。
Sentry 使用官方固定版本、校验和约束的二进制包；SwiftPM 首次可能下载该包的多个平台变体。

构建采用 Swift Release 优化、C `-O2 -g`，保留 C object，先生成 dSYM、校验 UUID/行表，再 strip 和签名。
所有产物在被忽略的 `build/` / `.build/` 内。
临时签名 + Hardened Runtime 在本机无法加载独立 C dylib，因此原型和 dylib 必须使用同一个 Developer ID。
没有关闭 library validation。签名不加 timestamp，不公证，产物只用于本机原型验证，不适合公开分发。
不能调用正式 `package-app.sh` 来构建此原型。

## 私有 Sentry 配置与远端验收

1. 在 Sentry 创建/确认私有项目 `okvideomac-macos`，仅使用 Error Monitoring。
   启用服务端 **Prevent Storing IP Addresses** 并确认项目访问权限。
   `sendDefaultPii=false` 不代表服务器收不到网络连接的源 IP；服务端也必须设置。
   真实后台验证还发现，仅禁止保存 IP 仍会补充地区信息，因此需添加项目级高级脱敏规则
   **[Remove] [Anything] from [$user.geo.**]**。必须以新事件验证；不会追溯修改旧事件。
   该行为见 [Sentry 上游说明](https://github.com/getsentry/sentry/issues/92201)。
2. 将 `Configuration/app.env.example` 复制到仓库外，`chmod 600`，只填 DSN。
   将 `Configuration/symbols.env.example` 另行复制到仓库外，`chmod 600`，填 org/project/token。
   Token 只用于开发机的符号上传，不能放入 App、用户配置包或公开仓库。
3. 安装官方 [sentry-cli](https://docs.sentry.io/cli/installation/)。运行：

   ```sh
   python3 Scripts/upload-symbols.py --config /absolute/private/path/symbols.env
   ```

   脚本先重验 App/dSYM，再执行官方 `debug-files upload --wait`。
   不使用 `--include-sources`，不上传源码包。到项目 Debug Files 页面核对
   `build/symbol-manifest.json` 中两个实际 UUID；dSYM 处理成功也不能替代下一步事件验证。
   若关闭了 Enable release auto-creation from telemetry，须先使用开发机私有凭据执行官方
   `sentry-cli releases new com.okvideomac.CrashVisibilityPrototype@0.1.2+3` 登记原型版本。
   初始验证中，未登记时后台缺少 Release/Dist；登记后已验证 0.1.0 (1) 与 0.1.1 (2)；0.1.2 (3) 也已在第 4 轮完成真实事件验收。
   上传令牌使用 org:ci，仅存在开发机的仓库外 0600 配置；不能随 App 分发。
4. 使用独立测试数据目录启动，先制造未授权崩溃，再次启动开启授权：

   ```sh
   open -n build/CrashVisibilityPrototype.app --args --ui --state-root /absolute/test/state \
     --config /absolute/private/path/app.env
   ```

   先测试 Swift，再测试 C。用界面明确开启开关。检查 Sentry 中正确的原版本/Build、
   crashed thread、Swift 关键调用函数、C `CrashFixture.c` 的真实行号，且没有禁传字段。
5. 再做未授权重启、撤回后重启、离线再上线和升级后旧报告上传的远端对照验收。
   本机回环接收器仅证明 SDK 发送了什么，不证明服务器最终展示和聚合结果。

参考：[Sentry 调试文件上传](https://docs.sentry.io/cli/dif/)、
[Sentry 数据隐私](https://docs.sentry.io/platforms/apple/guides/macos/data-management/sensitive-data/)、
[PLCrashReporter](https://github.com/microsoft/plcrashreporter/tree/1.12.2)。

## 下一阶段之前不要做的事

不接正式 App，不改 AppState/MPV/shutdown，不接正式 Release 门禁，不发布原型，不更新桌面 App。
远端验收通过后，再单独评审真实 SwiftUI 入口改造及原有单实例保护顺序。
G0 没有收集真实 libmpv、FFmpeg、Bridge 或 Android 子进程崩溃，也没有验证这些模块的 dSYM。
Loader/dyld、Gatekeeper、安装 reporter 之前的崩溃、SIGKILL、系统断电不在覆盖范围。
如果用户永不重启或一直在捕获器安装之前失败，就无法由本方案完成上传。
