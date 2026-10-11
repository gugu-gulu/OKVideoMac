# 初始 G0 / 手动恢复 UI 验收（历史记录）

本页保留 0.1.0 / Build 1 的原始结果、UUID 和手动验证，不代表当前重新构建的二进制。
最新异常路径与启动演练见 [PHASE1-2-ACCEPTANCE.md](PHASE1-2-ACCEPTANCE.md)。

# G0 本地与真实 Sentry 后台验收记录

日期：2026-10-11。基线：开源 `main` commit `3ae794b`；工作分支：`codex/crash-visibility-g0`。
正式 OKVideoMac 版本仍为 **0.8.4 / Build 137**。独立原型 Bundle ID 为
`com.okvideomac.CrashVisibilityPrototype`，原型版本 **0.1.0 / Build 1**。

**结论：本地原型与真实 Sentry 核心闭环验证通过；保持原型隔离，不接入正式 App。**

## 已通过

- Release Swift 单元测试：**12/12**。
- 已打包、签名 Release App 集成测试：**17/17**，包含 12 轮连续崩溃/恢复；一次完整回归共 32 次受控故障。
- 首次运行在模拟 bootstrap 前后发生 Swift/C 崩溃，下一次启动检测并恢复报告。
- 未授权：实际本机接收器观察到 **0 请求**，SDK 不启动。
- 授权：由官方 Sentry SDK 发出白名单事件；下一次启动不重复发送已收到 HTTP 回执的同一事件。
- 故意向 SDK scope 注入的身份、URL、Token 文本和 breadcrumbs 均未出现在最终出站事件中。
- HTTP 503 保留白名单报告，重试保持同一 event ID；没有把 capture() 返回 ID 或 flush() 返回当作服务器成功。
- 撤回授权后取消专用发送会话、清理待发记录和 SDK 缓存；在途撤回后不继续重试。
- 旧版元数据模拟升级后仍然保留，未被当前进程版本/Build 替换。
- 报告损坏、存储不可用时不产生诊断自身的启动循环；未改变真实 App 的恢复行为。
- Signal、Mach、NSException 捕获器在 SDK 启停前后保持一致；SDK 活动期间/关闭之后真实 C 崩溃仍由 PLCrashReporter 捕获。
- App 和 C dylib 使用同一现有 Developer ID 签名，Hardened Runtime 开启，严格签名校验通过；没有关闭 library validation。
- 两个发布二进制与各自 dSYM UUID 精确匹配，具备自己源码的行表；实际崩溃地址可本地符号化。
- 原型上传脚本 `--check-only` 通过；Python/Bash 脚本语法通过。
- 所有改动局限于 `Tools/CrashVisibilityPrototype/`；未改正式工程、版本、播放器、发布流程或商业隔离目录。

## 符号化证据

Swift Release 优化会使部分帧显示 `<compiler-generated>:0`，不能声称每个帧都有精确源码行。
本次能够定位 Swift 关键函数及其 `Entry.swift` 调用位置，C 故障能定位到具体源文件行。

### CrashVisibilityPrototype

UUID：`E231046D-241B-32B5-AA86-FB5AC1024A22`

```text
specialized static PrototypeEntry.swiftCrashFixture() (in CrashVisibilityPrototype) (/<compiler-generated>:0)
specialized static PrototypeEntry.main() (in CrashVisibilityPrototype) (Entry.swift:31)
CrashVisibilityApp_main (in CrashVisibilityPrototype) (Entry.swift:0)
```

### libCVPCrashFixture.dylib

UUID：`BCBF6240-FF35-3F0E-A3AF-79EF1DC501DC`

```text
cvp_faulting_write (in libCVPCrashFixture.dylib) (CrashFixture.c:6)
cvp_crash_fixture (in libCVPCrashFixture.dylib) (CrashFixture.c:13)
```

## 真实 Sentry 核心闭环（2026-10-11）

- 用户授权创建 org:ci 上传令牌，DSN 与 Token 分开保存到仓库外 owner-only 文件；不在源码、App 或输出中展示。
- 官方 sentry-cli 3.8.0 下载 SHA-256 核对通过；debug-files upload --wait 完成。官方只读 Debug Files API 再次确认最终两个 UUID 均有 debug 信息。
- 最终 Swift：OKVIDEOMAC-MACOS-3，event `f3366d027f15bfd37af5b3d0c39768b7`，定位 `PrototypeEntry.swiftCrashFixture / Entry.swift:65`；调用方 `Entry.swift:31`。
- 最终 C：OKVIDEOMAC-MACOS-4，event `b1c65cc21fe2dfc91f6251a60935e558`，定位 `cvp_faulting_write / CrashFixture.c:6`，调用方 `CrashFixture.c:12`（后台返回地址修正与本地 atos 的显示可不同）。
- 两者显示 `0.1.0 (1)`、`dist=1`、macOS 14.8.9、arm64、崩溃线程；Grouped by 明确包含 exception stacktrace。最新事件无 User/Geography，Attachments=0、Replays=0。
- 未授权重启恢复本地报告，SDK 不启动；授权后 HTTP 200，后台实际显示；已收到回执后再次启动没有重复发送。
- 两份最终事件在 SDK scope 中注入了合成禁传字段，用原有 beforeSend 白名单重建；本地实际网络断言仍通过。
- 最终两个 Issue 事件数各 1。本轮全部 6 个独立远端测试目录均撤回授权，pending=0、sdkStarted=false。
- 早期配置与旧分组试验记录保留为诊断证据，不作为最终验收事件。未启用 Performance、Profiling、Replay 或行为采集。
- 完整本地后台证据：`build/sentry-backend-20261011/`（已忽略，包括最终 UI 状态、截图、发送回执、UUID 与签名记录）。

## 恢复提示与授权界面验收（2026-10-11）

使用同一签名 Release 原型、独立 `build/recovery-ui-20261011/live-ui` 数据目录，逐步验证后再继续。
原生 UI 控制工具超时，因此按钮点击由用户完成；界面状态由用户反馈及截图确认，本地文件与 Sentry 页面由助手核对。

| 步骤 | 实际结果 | 证据 |
| --- | --- | --- |
| 初始关闭授权，点击 Swift 崩溃后重启 | 恢复提示出现；开关未勾选；待处理 1；原始报告解析后清除 | 用户确认 + `step1-recovery.json` |
| 在恢复界面开启授权 | 显示接收端已确认；待处理 0；授权持久化为 true；发送缓存清除 | `step2-grant.json` + 真实 Sentry 事件 |
| 关闭授权 | 显示撤回并清理提示；授权持久化为 false；待处理 0；缓存为空 | 用户确认 + `step3-revoke.json` |
| 保持关闭，点击 C 崩溃并重启 | SIGBUS 报告恢复到本机；授权仍关闭；待处理 1；无发送缓存 | `step4-revoked-restart.json` + 用户截图 |
| 撤回后的后台对照 | 用新 C 报告精确 ID 查询，观察时无匹配事件 | 后台查询截图/状态文件；不将有限观察表述为永久保证 |

开启授权后实际上传的 Swift event：`c9d3ac7d7cb1c23d70fb2e57cd693c66`，
[OKVIDEOMAC-MACOS-3 中的本次事件](https://okvideo.sentry.io/issues/7786275346/events/c9d3ac7d7cb1c23d70fb2e57cd693c66/)。
版本 `0.1.0 (1)`、dist 1、线程 0、`PrototypeEntry.swiftCrashFixture / Entry.swift:65` 均正确；
GUI 入口帧为 `Entry.swift:25`。按 exception stacktrace 分组；页面无 User/Geography，Attachments/Replays 均为 0。
该 Issue 包含此前 CLI 事件及本次 GUI 事件，共 2 条，不是本次报告重复发送。

撤回后新 C event：`242dfdbba9ab7a5616ca04018a44863a`，只保留于本轮本地测试目录。
最终用户截图清楚显示恢复标题、未勾选授权、待处理 1，以及“继续打开原型”按钮。
用户先前反馈找不到继续按钮，随后成功点击 C 崩溃按钮；重启后的截图已确认继续按钮存在，本轮未复现恢复页按钮缺失。

本轮没有修改程序源码或重建二进制，因此沿用上轮已通过的 12 项单元测试和 17 项集成测试结果，未声称重新运行。
本轮开始时再次通过原型签名、Hardened Runtime、UUID 和行表检查；正式工程、播放器、发布脚本和桌面 App 均未改变。
测试结束时原型仍停留在恢复界面，授权关闭、待处理 1，保留现场供用户查看；没有再次开启授权来清队列。
截图和过程记录位于被忽略的 `build/recovery-ui-20261011/`。

## NOT_TESTED / 明确边界

- **完整服务端 JSON 逐字段导出复核**：当前 org:ci 令牌不含事件读取权限（403），浏览器 JSON 导出本轮未成功；未扩大令牌权限。客户端实际 SDK 出站白名单由集成测试验证，后台版本/线程/关键栈/附件及用户地理信息通过已登录页面核对。
- **离线再上线、模拟升级后旧报告的真实远端对照**：仅完成本地接收器验证，不计为远端通过。
- **恢复提示的全自动界面操作**：原生 UI 控制工具超时。本轮由用户实际点击、反馈并提供最终截图，配合本地状态和真实后台核对完成手动界面验收；不能计为全自动 UI 测试通过。
- **正式 AppState/bootstrap、真实播放器、Bridge/libmpv/FFmpeg、子进程**：本轮未接入；测试中的 bootstrap 是独立模拟入口。
- **macOS 12 实机、Intel**：只在 macOS 14.8.9 / arm64 / Xcode 16.2 上运行验证。
- **Notarization、Staple、公开分发**：未执行；原型使用无 timestamp 的本地 Developer ID 签名，不是正式 Release。
- dyld/Loader、Swift Runtime/全局初始化中早于 main 的部分、reporter 安装前、SIGKILL、断电均不在覆盖范围。
- HTTP 回执不是后台符号化成功；断网或进程在回执持久化前终止可能产生重复尝试，沿用 event ID，不承诺网络恰好一次。
- 撤回不能撤回服务器已经收到的数据。本轮早期两份 Swift 配置试验事件仍保留当时的地区信息；新脱敏规则仅作用于后续事件，没有删除历史证据。
- 组织的 Allow Shared Issues 仍开启，未生成任何匿名分享链接；正式接入前建议由组织管理员关闭该能力。项目所关联团队本轮检查只有当前用户。

## 本轮发现并修复的原型问题

1. SwiftPM 注入的 Objective-C 资源头使 PLCrashReporter C/C++ 编译失败：改用同一固定 commit 的上游 Xcode 静态框架目标，未改依赖源码。
2. Mach port 查询后立即释放导致名称重新编号，产生 handler 检查假失败：探针现在保留 send rights 到比较结束，再释放。没有修改实际 handler。
3. C 编译临时 object 被清理导致空 dSYM：保留优化后的 object，再运行 dsymutil；没有放宽行表门禁。
4. 临时签名 C dylib 无法被 Hardened Runtime 原型加载：改为同团队 Developer ID 签名，没有禁用库验证。
5. 真实 Sentry 原先只按 exception message 分组：事件映射仅设置 threadId，异常自身缺少 stacktrace。先补回归并在旧原型复现失败，再复用原有白名单崩溃线程堆栈、标记自有模块帧；客户端回归及后台 stacktrace 分组均验证通过。没有新增日志或内容采集。
6. 服务端配置：禁止保存 IP 不会自动移除地区信息，改用 $user.geo.** 移除规则并以新事件验证；关闭自动创建 Release 时，需先显式登记原型版本。

## 产物与复验

- App：`build/CrashVisibilityPrototype.app`
- dSYM：`build/symbols/`
- 构建/签名/UUID 记录：`build/package-verification.json`
- XCTest：`build/unit-tests.log`
- 集成测试：`build/integration-tests.log`
- 本地符号化：`build/local-symbolication.json`
- 最终符号门禁：`build/symbol-check.log`

上述构建产物和测试数据都被 gitignore 排除。没有提交、推送、Tag/Release 或桌面安装操作。

二进制 SHA-256（整个 App 目录不能用单一文件 hash 表示）：

- `Contents/MacOS/CrashVisibilityPrototype`：`e97dcc7ed990add147015ea9f205cc6794f8cb0c9989de7355180d9555f17ec1`
- `Contents/Frameworks/libCVPCrashFixture.dylib`：`01464dfdb0c4cd8c3673d23a4d14ad33e9969d5deefb309129d3b4d666ef04a7`

下一步：恢复提示及授权开关的手动界面验收已通过；未测试的远端异常路径按上述边界保留，再单独评审正式 App 接入。本轮没有正式接入、安装、公开发布或修改正式版本。
