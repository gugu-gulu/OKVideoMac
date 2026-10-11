# 第 3 步：上传异常路径与恢复界面

后续同一 0.1.2 二进制的真实 Sentry 和资源复验已完成，见 [第 4 轮验收](PHASE4-ACCEPTANCE.md)。下文保留第 3 步当时的范围与限制。

日期：2026-10-11。分支 `codex/crash-visibility-g0`。独立原型 **0.1.2 / Build 3**。
正式 App **0.8.4 / Build 137** 未修改；未替换桌面 App，未修改商业目录，未提交、推送或发布。

## 当前门禁

- 上传进程异常路径：PASS。
- 新单窗口启动模型：PASS。
- 全部既有回归：PASS。共 74 项自动测试通过。
- 新单窗口继续/视觉：PASS（用户实测同窗切换，显示正常，无需 Dock）。
- 新单窗口测试页 Command-Q：PASS（用户操作、退出轨迹和进程消失一致）。
- 新单窗口恢复页红色关闭：PASS（退出且未初始化模拟业务、未上传、报告保留）。
- 新单窗口开启授权：PASS（两份预期合成报告各收到一次，队列/缓存/子进程清理完成）。
- 新单窗口关闭授权：PASS（关闭状态持久化，队列/缓存为空，无发送子进程或新增接收）。
- 撤回后正常重启及新 C 崩溃重启：PASS（程序化复核；授权仍关闭，新报告只保存在本机）。
- 预启动 AppKit 模态窗口 → SwiftUI 的旧交接：**NOT_ACCEPTED**，已移除，不能记为通过。
- 当前 0.1.2 真实 Sentry 后台和新 UUID 上传：NOT_TESTED。本轮仅本机回环接收器，历史后台结果见第 1、2 步报告。

## 修改与依据

### 上传子进程

原实现先在主线程向管道同步写入，再建立超时；子进程不读取且报告填满管道时，主线程和截止处理都会被堵塞。
`UploadProcess` 将启动、非阻塞 I/O、截止检查和回收移至后台，截止时间先于启动/写入建立。
输入上限 1 MiB，输出上限 4096 字节；只对管道设置 F_SETNOSIGPIPE，不更改全局信号处理器。
撤回先持久化关闭授权并取消发送，等待子进程退出后清理队列/缓存；快速重新开启必须排在清理之后。
父进程退出检测补充在读取输入之前安装，处理子进程不读输入时的退出边界。

保留唯一 PLCrashReporter 捕获器、官方 Sentry SDK 传输及事件字段白名单；未增加日志、播放状态或用户信息采集。
测试观察到约 1 MiB 堵塞输入在 8 秒截止内结束，主线程心跳保持；20 轮异常发送前后 FD 均为 5。
确切耗时和每次场景结果保存在本轮日志中，不以这些本机数值承诺所有系统的调度延迟。

### 恢复窗口

用户观察到旧恢复窗口仍留在屏幕，新的 SwiftUI 界面直到点击 Dock 才出现。
之前的激活、置前和延迟交接尝试均未通过；active/visible/key 内部标志不足以证明视觉正常。
不能将问题归因为已证实的系统 bug。失败实现和证据保存在 `build/phase3-20261011/rejected-native-handoff/`。

当前改为 `RecoveryShellApp` 的单个 WindowGroup，在同一个视图根节点内切换恢复提示和测试内容。
已删除 NativeRecoveryGate；没有 runModal、自建恢复 NSWindow、焦点重试或延时窗口交接。
捕获器和单实例租约仍在 App.main 前；App.init 只建立轻量壳，模拟业务由“继续”触发且最多一次。
**恢复 UI 已移到 SwiftUI 启动后，业务仍延迟。** 正式 App 尚未做这种调整，需要另行评审。

## 自动验证

| 测试 | 最终结果 |
| --- | --- |
| Swift Release 单元 | 20 项通过 |
| 原有崩溃/恢复/SDK 出站回归 | 27 项通过 |
| 原有真实 SwiftUI 启动顺序 | 9 项通过，原验收断言保留 |
| 新上传进程异常路径 | 10 项通过 |
| 新单窗口启动模型 | 8 项通过 |
| Release 包 | 精确 2 个 Mach-O；Developer ID、Hardened Runtime、严格 codesign、dSYM UUID/行表、加载路径通过 |

上传新增场景包括：无法创建子进程、不读大输入、读前/读后退出、不回包、损坏/过大输出、堵塞中撤回、
快速重新授权、父进程退出、20 轮创建销毁、大报告实际官方 SDK 发送。既有回归继续检查
无授权零请求、网络失败保留报告、同 ID 重试、字段白名单和本地 Swift/C 源码行解析。

单窗口新增场景包括：提示时无模拟业务、继续两次仅初始化一次、确认后正常重启不阻挡、新崩溃再次提示、
五个早期故障、捕获存储失败继续业务、提示期间保留原单实例租约、10 次干净启动。
自动决定明确注入在模型层；**不是 GUI 点击，也不是视觉验收**。
本轮第一次旧启动测试的证据目录缺少 provenance 文件而失败，补齐真实构建清单后原断言通过；失败日志保留。

## 人工验收记录

旧 AppKit 恢复窗口的红色关闭、回车、授权开启/撤回曾经通过；Command-Q 失败后修复并手动通过。
这些结果只属于已归档实现，不移植成新单窗口的通过记录。
新单窗口继续/视觉已通过：用户确认同一窗口直接切换、显示正常、无需 Dock。
本地轨迹确认继续之后才执行模拟业务，bootstrap/模拟播放器均为 1 次；授权仍关闭，待处理 1、回环接收 0。
新单窗口测试页 Command-Q 已通过：用户确认正常退出；delegate-will-terminate 已记录，PID 77257 已退出，授权关闭、待处理 1、接收 0。
新单窗口恢复页红色关闭已通过：用户操作后 PID 78231 退出，delegate-will-terminate 已记录，无 bootstrap/数据库/播放器标记；授权关闭、待处理 2、接收 0。
新单窗口开启授权已通过：用户确认已接收且待处理 0；本机实际 SDK 回执与两份预期事件 ID 完全一致，各收到一次。授权持久化 true，缓存和上传子进程均无残留，模拟业务尚未初始化。接收器仅在本机，不代表新版本 Sentry 后台验收。
新单窗口关闭授权已通过：用户确认提示和待处理 0；本地 consent=false，队列及缓存为空，无上传子进程，接收总数仍为 2。

随后用同一份测试状态做程序化复核（不是人工点击）：结束已验收进程，正常重启确认授权仍关闭且只初始化一次；
再注入 C 合成崩溃，重启确认恢复提示出现、业务未初始化、授权仍关闭、待处理 1，接收端无新增事件。
最后关闭原型和本轮回环接收器。新报告保留在隔离目录，仅本机保存，没有修改正式用户数据。
证据：`build/phase3-20261011/single-window-ui/manual-*.json`、`post-revoke-restart.json`、启动轨迹及接收记录。

## 已知限制

- 一次常规 leaks 检查观察到 144 字节；未改动的 0.1.0 基线同样出现。另一次启用分配栈记录的检查为 0。
  现有证据未显示本轮新增该项，也未证明其具体来源，故不声称“完全无泄漏”。正式长期泄漏分析未做。
- 只在 macOS 14.8.9 arm64、Xcode 16.2 验证；其他系统/正式 App/播放器/Sparkle/商业目录均不在本轮范围。
- 本地签名无 timestamp、未公证，原型不可作为公开发行包。
- 当前新构建远端 Sentry NOT_TESTED；HTTP 2xx 不等于后台符号化或网络恰好一次；撤回无法撤回已经送达的数据。
- reporter 安装前、dyld/Loader、签名/Gatekeeper、SIGKILL/断电以及用户不再重启仍不覆盖。

## 当前本机产物

`build/CrashVisibilityPrototype.app`，只用于独立验证；dSYM 在 `build/symbols/`。

| Mach-O | UUID | SHA-256 |
| --- | --- | --- |
| `Contents/MacOS/CrashVisibilityPrototype` | `FF079DA8-1A9E-3432-97D1-21D8B9F4B062` | `dbb46c1744c08baf610f6e66670ec6f1207d9092a3d5a545099c31ee283a4b1c` |
| `Contents/Frameworks/libCVPCrashFixture.dylib` | `D3DF3700-2D66-30C3-94A4-2A22E8ABF0E8` | `91f2ab7a34f85e2a9792d8d0dfee1b204480cbf9241bd7643c05c732dc1158e3` |

证据位于被忽略的 `build/phase3-20261011/`；源码不含报告、凭据或构建产物。
主要新增文件：`UploadProcess.swift`、`UploadProbe.swift`、`RecoveryShellApp.swift`、
`test-upload-process.py`、`test-recovery-shell.py`、`native-ui-sink.py`。
相关修改限于原型 `SentryAdapter`、`SentryUploadWorker`、`RecoveryCoordinator`、`Entry`、`PrototypeApp`、
`StartupRehearsal`、单元测试、元数据脚本和本目录文档。
