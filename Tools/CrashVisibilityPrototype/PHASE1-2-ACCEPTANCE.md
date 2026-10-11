# 第 1、2 步验收：原型异常路径与启动顺序

日期：2026-10-11（Asia/Shanghai）。分支：`codex/crash-visibility-g0`。
范围：仅 `Tools/CrashVisibilityPrototype/`；正式 App 仍为 **0.8.4 / Build 137**。
先完成第 1 步本地及真实后台核对并保存 PASS 门禁，再开始第 2 步。
没有接入正式 App，没有改商业目录、播放器生命周期或正式发布流程，没有替换桌面 App。

## 结果

| 验证 | 结果 |
| --- | --- |
| Swift Release 单元测试 | 19 项通过 |
| 实际签名原型崩溃/恢复/上传集成测试 | 27 项通过，保留全部原有验收条件 |
| 实际 SwiftUI 启动顺序演练 | 9 项通过，含 5 个故障点和 10 轮正常启动 |
| 打包完整性 | 精确 2 个 Mach-O、Developer ID、Hardened Runtime、严格 codesign、UUID/行表通过 |
| dSYM | 最终两个 UUID 已由官方 CLI 上传并等待处理成功；没有上传源码包 |
| 真实 Sentry | 旧版报告、新版失败重试、最终 App.init 崩溃均收到并正确符号化 |
| 凭据/修改边界 | 待交付源码未包含本机私有 DSN/Token；正式已跟踪文件 diff 为空 |

原型版本为 **0.1.1 / Build 2**。本轮旧版升级验收使用归档的真实 **0.1.0 / Build 1** 二进制与报告，
不是仅篡改版本字符串。原型反复构建期间 UUID 会改变，以本页最终 UUID 和 package-verification 为准。

## 第 1 步：发现、修复及验证

- 修复同一份报告在每次正常重启时重复阻挡的问题。恢复提示确认与上传授权分别存储；
  继续启动不会开启上报或删除报告，新崩溃仍重新提示。
- 将界面状态提取为同一套 `RecoveryCoordinator`，用于 SwiftUI 与进程测试；
  已有授权自动发送、撤回后清理、发送结果文案、继续启动只执行一次均被验证。
- 真实连接拒绝测试发现原型自身崩溃：先使 URLSession 失效，再调用 Sentry.close()；
  SDK close 即使超时为 0 仍异步 flush，后台再次创建 task 触发
  `Task created in a session that has been invalidated`。
- 修复采用**一次上传一个短生命周期进程**：SentryUploadWorker 只启用官方 SDK 发送，不安装 PLCrashReporter；
  主进程仍是唯一崩溃捕获方，掌握授权、确认回执与重试队列。没有自写 Envelope/HTTP 上传协议，未改 SDK。
  关闭授权时结束并等待上传进程退出，之后清队列和 SDK 缓存；父进程结束会通过管道 EOF 结束子进程。
  单次等待上限 8 秒，网络/SDK 内部超时仍独立限制；发送等待不妨碍继续启动。
- 测试覆盖无授权零请求、已有授权、503、连接拒绝、慢响应、发送中撤回、撤回后再次崩溃、
  缓存清理、畸形报告、存储失败、升级元数据、原型捕获器不受影响、21 次连续离线尝试、无上传子进程残留。
- 实际 SDK 出站事件仍逐字段白名单检查；原始 crash、日志、内容、配置、Token 等不发送。

两处测试脚本问题也保留了失败证据：同秒崩溃时间戳不能用于可靠区分 Swift/C 样本，改用隔离状态/事件身份；
新增 21 次尝试的用例改用累计时限，原有单次进程的 20 秒时限未放宽。源码行、栈与隐私断言未减少。

## 第 2 步：实测启动顺序

分析和具体边界见 [STARTUP-ANALYSIS.md](STARTUP-ANALYSIS.md)。

- 正式原有 `ApplicationInstanceLease` 类原样投影到原型构建，源文件哈希与类内容均核对。
  一次取得租约，将同一个对象交给模拟环境，不重复加锁。
- 实际 SwiftUI 运行表明：本机 StateObject 的 bootstrap 在 App.init 返回后执行；
  AppDelegate 初始化还晚于 bootstrap。不能依赖 AppDelegate 安装捕获器。
- 演练顺序为租约 → PLCrashReporter → 恢复决定 → App.main → App/State 初始化；
  重复/同时启动的第二实例不能进入捕获或模拟数据库。
- 五个真实故障点为 App.main 前、App.init、bootstrap 前/后及 AppDelegate.init，重启均恢复到本地。
- 捕获存储损坏可继续模拟业务；业务实例锁失败则必须停止。十轮真实 SwiftUI 启动后租约均可再次取得。
- 最后补查发现演练入口漏传既有模块地址清单。先由新增断言在五个故障点复现，再复用原型的版本/模块元数据；
  本地断言和最终真实后台 App.init 堆栈均通过。

本步骤的恢复决定是**测试注入**，不是原生模态恢复窗口的自动点击验收。
数据库和播放器是显式模拟标记，没有打开真实数据或改变播放器生命周期。

## 真实后台证据

| 场景 | 后台结果 |
| --- | --- |
| 归档 0.1.0 的崩溃，由 0.1.1 恢复上传 | [event 06d965ec](https://okvideo.sentry.io/issues/7786275346/events/06d965ec82cbbfedaf5850eb229d9efe/)：仍为 0.1.0 (1)，`PrototypeEntry.swiftCrashFixture / Entry.swift:65` |
| C 崩溃发送失败后恢复上传 | [event 5547e137](https://okvideo.sentry.io/issues/7786277093/events/5547e137ffa4b893397e635adb8e26af/)：0.1.1 (2)，`cvp_faulting_write / CrashFixture.c:6`，事件 ID 未改变 |
| 最终二进制真实 SwiftUI App.init 崩溃 | [event 75b1a6aa](https://okvideo.sentry.io/issues/7786325249/events/75b1a6aa687821450a1e61b3040272bb/)：0.1.1 (2)，`StartupRehearsal.fault:25 → StartupRehearsalApp.init:100` |

三个事件均按异常栈分组，页面未显示 User/Geography，Attachments/Replays 为 0。
网络故障用回环端口连接拒绝注入，再切回真实 Sentry 上传；没有切断系统网络，不能表述为真实断网硬件测试。
本轮远端测试目录结束时均已撤回授权、待处理为 0；之前用户手动验证的恢复现场未清理。

## 最终本机产物

`build/CrashVisibilityPrototype.app`：本机 Developer ID 签名 Release，**不公证、不公开分发、不安装桌面**。

| 文件 | UUID | SHA-256 |
| --- | --- | --- |
| `Contents/MacOS/CrashVisibilityPrototype` | `18169232-A36E-3069-B412-39DBC259F302` | `347cab4bf3aa297acf9a4b52a5b7b3447cd15083c7e9c55fb2bd246f4b2d9824` |
| `Contents/Frameworks/libCVPCrashFixture.dylib` | `2E79F9AC-1646-36E4-99F5-408CFF26E390` | `11b8925f1ee2787fe5161d146f9b5498e706255097b02b9e47868b8e4597c6da` |

证据位于被忽略的 `build/phase1-20261011/`、`build/phase2-20261011/`，
包括失败回归、完整测试日志、启动轨迹、实际旧二进制、包清单、后台 AX/截图和事件 ID。

本轮主要文件：`RecoveryCoordinator`、`ReportStore`、`SentryAdapter`、`SentryUploadWorker`、
`Entry`、`PrototypeApp`、`StartupRehearsal`，以及原型测试、构建/元数据脚本和本目录文档。
正式 README/CHANGELOG 不宣称已接入崩溃收集。未提交、推送或发布。

## 仍未验证 / 下一阶段边界

- 正式 App 集成、实际 AppState/SQLite/播放器、NSWorkspace 旧版本实例策略、正式本地化及菜单、Sparkle/异步退出。
- 新代码原生恢复 UI 自动点击、AppKit 模态提示到正式 SwiftUI 的交接：NOT_TESTED。
  本轮验证共享界面状态逻辑和注入决定的启动顺序；之前手动 UI 验收属于旧原型，未冒充新 UI 全自动结果。
- Bridge/libmpv/FFmpeg/Android 子进程符号化、真实用户崩溃、完整泄漏分析及大规模长期运行。
- 其他系统/架构：仅 macOS 14.8.9 / arm64 / Xcode 16.2 实测。
- 服务端完整事件 JSON 导出：org:ci 没有读取权限，未扩大权限；仍结合客户端出站白名单和后台可见字段验证。
- dyld/Loader、签名/Gatekeeper、main 前 runtime/全局初始化、捕获器安装前、SIGKILL、断电不在覆盖范围。
- 2xx 不等于恰好一次；回执丢失可能再次尝试，沿用同一事件 ID。撤回不能撤回服务端已经收到的数据。
- 上传子进程方案已在原型中验证；正式接入前需另行评审正式签名/沙盒/启动开销与进程退出边界。

下一步应单独评审正式接入方案；本轮不自动开始第 3 步。
