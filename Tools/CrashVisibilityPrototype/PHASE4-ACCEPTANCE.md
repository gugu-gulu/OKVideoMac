# 第 4 轮验收：固定 0.1.2、真实 Sentry 复验与原型收尾

日期：2026-10-11（Asia/Shanghai）。范围：独立原型 **0.1.2 / Build 3**，不接正式 App。

## 结果与分支

本轮计划第 1～3 步完成。先通过源码/Release 固定门禁，再上传符号和验证真实事件，最后完成资源对照及源码收尾。

- 工作区：`opensource-sparkle-stage2/ok影视 mac 版本`；分支 `codex/crash-visibility-g0`。
- 基线为当前远端 main `3ae794bcc9fc8c31165ddf36ebdd57b8423adb0d`，正式 App 为 0.8.4 / Build 137。
- 用户最新弹幕修改在 `codex/danmaku-shadow-retina`，尚未提交。已将其两个文件原样复制到当前工作区并核对 SHA-256：
  `Features/Player/DanmakuPlayerSupport.swift`、`Tests/OKVideoMacTests.swift`。
  这两项作为用户已有改动保持未暂存，不纳入原型提交；原弹幕工作区未改动。
- 原型捕获、上传、恢复窗口的运行逻辑及已验收二进制均未改动。提交前 whitespace 检查发现 `RecoveryCoordinator.swift` 末尾多余空行，仅删除该空行，没有移动任何代码行；新增验收文档，更新 README 与历史报告链接。
- 未运行正式 App 打包流程、未替换 Desktop App、未修改商业目录、未推送、未创建 GitHub Release。
  Sentry 中登记的是合成测试原型版本，与公开软件发布不同。

## 第 1 步：固定当前产物

归档 37 个可交付源码/配置示例/文档文件、`Package.resolved`、Release App、两个 dSYM 和逐文件 SHA-256。
排除真实 DSN/Token、原始报告、缓存、构建产物；现有私有配置仍在仓库外且权限 0600。
核对实际 bundle 全部文件，精确包含两个 Mach-O；严格签名、Developer ID、Hardened Runtime、加载路径、UUID 与源码行表通过。
源码、依赖、构建记录及最终产物对应记录存放于忽略目录；没有把旧版本验收当作本轮二进制证据。

| 模块 | UUID | SHA-256 |
| --- | --- | --- |
| CrashVisibilityPrototype | FF079DA8-1A9E-3432-97D1-21D8B9F4B062 | dbb46c1744c08baf610f6e66670ec6f1207d9092a3d5a545099c31ee283a4b1c |
| libCVPCrashFixture.dylib | D3DF3700-2D66-30C3-94A4-2A22E8ABF0E8 | 91f2ab7a34f85e2a9792d8d0dfee1b204480cbf9241bd7643c05c732dc1158e3 |

未重建这套产物。上一轮 **74 项通过**的测试结果按相同运行逻辑与二进制哈希沿用（源码唯一空白整理见上文）：20 单元、27 集成、9 启动、10 上传异常、8 单窗口。
本轮没有将它们计作重新运行；日志及其哈希见 `build/phase4-20261011/reused-tests.json`。

## 第 2 步：真实 Sentry

现有私有项目 `okvideo/okvideomac-macos`；只发送两份合成崩溃报告。
官方 sentry-cli 3.8.0 的 `debug-files upload --wait` 明确返回两个 UUID 均处理完成；未上传源码包。
登记 `com.okvideomac.CrashVisibilityPrototype@0.1.2+3`，没有扩大原有 org:ci 权限。
上传最初被自动审批拒绝；用户在本聊天明确授权具体 dSYM、项目、版本登记与合成事件后再执行。

| 场景 | 实测结果 |
| --- | --- |
| 未授权 SwiftUI App.init 崩溃 | 捕获在先，重启显示单窗口恢复状态；模拟业务未初始化，授权 false，报告本地保存 |
| Swift 开启授权发送 | [事件 d19e17b5](https://okvideo.sentry.io/issues/7786465706/events/d19e17b51751dbb283f6a2f495ad2646/)：0.1.2 (3)，Thread #0，`StartupRehearsal.fault / StartupRehearsal.swift:25`，`RecoveryShellApp.init / RecoveryShellApp.swift:49` |
| C 先失败再重试 | [事件 8f6375f1](https://okvideo.sentry.io/issues/7786277093/events/8f6375f1a15b7f44320592565079313f/)：0.1.2 (3)，Thread #0，`cvp_faulting_write / CrashFixture.c:6`，`cvp_crash_fixture / CrashFixture.c:12`；失败保留、重试 ID 不变 |
| 实际模块匹配 | 后台 Images Loaded 中两个自有模块均为 Ok / Symbolication；Debug ID 与上表逐一相同 |
| 撤回后再 C 崩溃、重启 | 授权 false、待处理 1、无 SDK 缓存；本地 ID `106cd778747c8fcd74278a657f1ed5fa`，后台精确查询无结果 |
| 可见隐私字段 | 两个事件均无 User/Geography/Breadcrumb 区块；Attachments/Replays 均 0；上下文为 OS、架构及服务器 Trace Details |

C 的失败由本机已占用但未监听的端口注入，然后切回真实 Sentry。没有切断系统网络，不是物理断网测试。
本轮授权通过原型共享模型的命令行测试入口注入，不冒充人工点击。新的原生 UI 自动控制调用超时，未完成新一轮点击检查；上一轮同二进制的人工单窗口验收仍单独有效。
客户端字段白名单沿用同二进制的实际 SDK 出站测试；后台完整事件 JSON 未导出，不能将页面核对写成完整服务器存储审计。
撤回后保留的新合成报告只在隔离目录；两处真实 Sentry 测试状态的授权最终均关闭。

## 第 3 步：资源、兼容性和源码收尾

### 同条件泄漏对照

旧 0.1.0 与当前 0.1.2 使用相同 `--ui`、同一 leaks 工具/参数、无 MallocStackLogging，独立状态各启动 3 次，每次采样 2 次。
12 次结果均为 **1 块 / 144 字节**，无新增泄漏块；仍未定位该固定基线块的具体来源，不宣称零泄漏。

当前 0.1.2 单进程连续向本机 503 接收器执行 31 次真实 SDK 发送：同一事件 ID，失败报告保留、句柄数 6、线程数 5，退出后无子进程，撤回后队列/缓存清空。
采样在第 2/12/22 次附近，leaks 始终 144 字节，但活跃分配约 1595/2812/4167 KiB，存在随 CLI 循环增加的临时对象。

为判别原因，在 `build/phase4-20261011/pool-experiment/` 生成隔离 Release 对照：
仅在 **CLI 测试重试循环**增加 `autoreleasepool`，复用未改动的 core/SDK 对象文件。
同样 31 次、同参数、同接收器，活跃分配约 **1447/1454/1454 KiB**，节点数 4971/5000/5000；泄漏仍为 144 字节。
这证明本次 CLI 增长可由临时 Objective-C 对象的释放池边界解释，未显示新增持续存活的上传核心泄漏。
该对照不是正式/原型交付二进制，没有上传其符号，也没有替换已验收 App；不把这一结果外推为正式 UI 长期内存验收。
将来扩展长时间 CLI 压测时应为测试循环加入局部释放池；本轮保留原 0.1.2 与 74 项门禁，未修改生产核心。

失败证据保留：第一次资源脚本的最终次数断言失败，未保留该次完整次数，不能推断原因。
诊断复跑完整记录为 31 请求/31 事件/同 ID、进程正常结束；未降低原有测试条件。
隔离对照的第一次链接因脚本误删 `@loader_path` 失败，修正参数后成功；未触碰固定产物。

### 兼容性

Package、Sentry 固定依赖及最终两个 Mach-O 的部署目标均为 macOS 12；源码使用的 SwiftUI task、WindowGroup 和相关 Foundation API 与该目标相容。
实际运行环境仍只有 macOS 14.8.9 / arm64 / Xcode 16.2。**macOS 12、其他系统和架构运行：NOT_TESTED。**
未升级 PLCrashReporter 1.12.2、Sentry Cocoa 9.30.1 或其他依赖。

## 交付与边界

原型源码整理为本地可回退提交，提交范围严格限于 `Tools/CrashVisibilityPrototype/`。提交前检查凭据、忽略规则、文件范围及文档链接；最终哈希保持不变。
证据目录：`build/phase4-20261011/`，含固定快照、源码清单、依赖、上传回执、实际事件 ID、后台页面观察、资源对照及失败记录。
详细既有测试与人工验收见 [PHASE3-ACCEPTANCE.md](PHASE3-ACCEPTANCE.md)，启动边界见 [STARTUP-ANALYSIS.md](STARTUP-ANALYSIS.md)。

正式 App 接入、正式单实例进程策略、播放器/Sparkle/退出流程仍未改动或验收；下一阶段需先设计这些边界。
libmpv/FFmpeg/Bridge/Android 符号化不在本轮范围。AirPods 连接、摘下/断开、重连、系统输出切换及人工听音均 **NOT_TESTED**。
本地产物无 timestamp、未公证，只用于独立验证；dyld/签名/安装捕获器之前故障、SIGKILL、断电及用户不再重启仍不覆盖。
