# 启动顺序演练：第 2 步

仅针对当前开源分支 `codex/crash-visibility-g0` 的独立原型。正式 App 为 0.8.4 / Build 137，未修改。

## 正式源码的事实

- `OKVideoMac/macOS/OKVideoMac/App/OKVideoMacApp.swift` 的 `@main OKVideoMacApp` 是正式 SwiftUI 入口。
- App 属性包括 `NSApplicationDelegateAdaptor`、`Environment(scenePhase)`、`StateObject<AppState>`。
- `init()` 先解析 `AppLocalizer.shared`，再把 `AppState.bootstrap()` 传给 `StateObject(wrappedValue:)`。
  后者是延迟创建，不能仅按源码位置断言 bootstrap 在 App.init 内执行。
- `AppState.bootstrap()` 调用 `AppEnvironment.live()`；失败时返回携带 startupError 的 AppState。
- `AppEnvironment.live()` 先计算目录、执行现有进程策略，再取得 `ApplicationInstanceLease`；
  然后才打开/恢复 SQLite，创建播放器、Android 等对象。环境持有租约。
- Window onAppear 安装 delegate/更新协调器，SwiftUI task 执行 `state.start()`；它们都晚于 bootstrap。
  退出仍沿用原来的异步 shutdown/terminateLater/fallback，未改动。

## 原型验证的顺序

`StartupRehearsal.swift` 使用真实 SwiftUI `App.main()`、`StateObject` 和 `NSApplicationDelegateAdaptor`，
用独立模拟 State/数据库/播放器标记替代正式业务。当前 macOS 14.8.9 实测：

```text
自定义入口
→ 取得原有单实例租约
→ 安装 PLCrashReporter
→ 如需恢复，等待决定（测试注入决定）
→ SwiftUI App.main()
→ App.init() 开始/返回
→ StateObject 内的 bootstrap
→ 同一个租约交给模拟环境
→ 模拟数据库/播放器标记
→ bootstrap 返回
→ AppDelegate 初始化
→ SwiftUI task
```

AppDelegate 的具体相对顺序由框架控制，不应成为业务依赖。重要结论是捕获器必须早于整个
SwiftUI App.main()，不能依赖 AppDelegate.init、didFinishLaunching、onAppear 或 task。
自定义 Swift 入口仍不能覆盖 dyld、链接/签名失败，以及先于 main 的 Swift runtime/全局初始化。

## 单实例保护与后续接入边界

构建时 `prepare-startup-rehearsal.py` 从正式 `AppEnvironment.swift` 原样提取整个
`ApplicationInstanceLease` 类，仅增加原型用错误/本地化桩；生成文件被忽略。
测试同时比较原类内容及源文件 SHA-256，避免用一个不同的“模拟锁”冒充正式锁。

演练只调用一次租约构造，并将同一个对象交给模拟环境，验证恢复提示等待期间，第二个实例
不能安装捕获器或触达模拟数据库。捕获目录损坏可继续启动；业务实例锁取得失败必须停止。
真实正式接入时，仍须单独设计如何在不创建完整 AppEnvironment 的情况下执行既有进程策略、
目录策略、取得并传递租约；不得简单新增一个锁后又让原 AppEnvironment 重复加锁。

本次没有执行正式 `ApplicationInstancePolicy` 的 NSWorkspace/旧版本进程识别，
没有打开正式 SQLite 或创建播放器，也没有改正式 App 的单实例/退出策略。

## 验证与限制

运行 `python3 Scripts/test-startup-rehearsal.py`。9 项用例覆盖：

1. 实际 SwiftUI/StateObject/DelegateAdaptor 的时序及只启动一次。
2. 恢复决定之前不进入 App.init/bootstrap；确认后正常重启不重复阻挡。
3. 五个真实故障点：App.main 前、App.init、bootstrap 前/后、AppDelegate.init；重启能恢复报告。
4. 恢复等待期间拒绝第二个进程，首个退出后正常取得租约。
5. 捕获目录故障继续启动。
6. 业务实例锁失败停止启动。
7. 十轮真实 SwiftUI 启动退出，无租约残留。
8. 原样租约投影与正式源码哈希一致。
9. 两个同时启动的进程只有一个能安装捕获并进入模拟数据库。

恢复决定通过测试输入注入，**没有把这项测试称为 AppKit 模态恢复窗口的自动点击验证**。
之前用户完成的原型恢复 UI 手动验收仍单独保留。本轮是启动顺序演练，不是正式接入验收。
其他 macOS 版本、正式本地化/菜单、Sparkle/退出流程、真实播放器、完整内存泄漏分析均未验证。


## 第 3 步调整：同一个 SwiftUI 窗口，延迟业务初始化

第 2 步的 9 项注入决定测试仍保留，不能把它们当作原生窗口交接已通过。
真实手动测试发现：预启动 AppKit 模态窗口仍可留在屏幕，新 SwiftUI 窗口需要点击 Dock 才出现。
即使内部记录 active/visible/key 为 true，也不足以证明实际视觉正常。该路径判为 **NOT_ACCEPTED**，
不是已修好的 OS 问题；未证明具体 AppKit 内部原因，已归档失败证据并删除原型的模态窗口交接代码。

当前 `--startup-rehearsal --recovery-shell-ui` 使用：

```text
独立入口 → 同一实例租约 → PLCrashReporter
→ SwiftUI App.main / App.init / 轻量 RecoveryShellState
→ 同一个窗口显示恢复提示（尚未创建模拟业务）
→ 继续：确认提示 → RehearsalState.bootstrap（最多一次）
→ 同一个窗口显示测试内容
```

没有原生自建 NSWindow、runModal、窗口置前重试、激活重试或延时交接。
恢复提示不再位于 App.main 前；**捕获安装仍位于 App.main 前**，实际 App.init 崩溃仍可在下次启动恢复。
五个早期故障点、等待期间单实例排他、继续不授权、继续只一次、确认后正常重启和新崩溃再次提示，
由 `Scripts/test-recovery-shell.py` 的实际 SwiftUI 启动及模型注入测试验证。
模型注入不是鼠标/键盘测试。后续独立人工验收已通过：同窗继续且无需 Dock、布局正常、
测试页 Command-Q、恢复页红色关闭和授权开启/撤回；本地轨迹与状态均核对，详见第 3 步验收报告。
正式 App 业务目前还从自己的 StateObject 引导；将来若采用轻量 Shell，必须单独评审该改动，不能直接替换正式入口。

## 固定二进制的后续复验

第 4 轮在同一 0.1.2 二进制验证了真实 `RecoveryShellApp.init` 崩溃的 Sentry 符号化，
对应 `StartupRehearsal.swift:25` 与 `RecoveryShellApp.swift:49`，详见 [PHASE4-ACCEPTANCE.md](PHASE4-ACCEPTANCE.md)。
正式 App 的启动与退出设计仍未接入；本轮没有把模型决定注入称为 GUI 点击。
