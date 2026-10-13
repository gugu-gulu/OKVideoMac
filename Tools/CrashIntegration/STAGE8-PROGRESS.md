# 第 8 步检查点：界面控制恢复，实机回归继续保留两项待办

2026-10-13，macOS 14.8.9 / arm64。状态 **PARTIAL_PENDING_SLEEP_WAKE_AND_SDK_PROBE**，第 9 步未开始。未替换桌面 App、未推送或发布。此记录不是最终 Release 验收通过证明。

## 已完成的自动化基线

三个 Release XCTest 运行覆盖 **420 个不同测试**，零失败。首轮 401 通过、5 跳过；实际 OpenGL/全屏/长关键帧拖动补跑 47 通过（44 个重复基线）；Android 生命周期补跑 60 通过（44 个重复基线）。两个未提供的外部 Node Contract B 样本未运行，不计为通过。此前独立原生全屏实际进入/退出 3 轮；本机没有捕获到共享动画采样，不宣称动画采样指标通过。

5 次开启捕获的隔离 Release 启动达到第 1 步未修改的固定阈值：首窗中位数 0.362 秒；空闲 RSS 90,336 KiB、CPU 0.0%、线程 9、FD 16、子进程 0。此前同一实际 Release 上传适配器的 30 次本机 503 均返回 pending 并保留同一报告 ID，主线程最大间隔 13.5 ms，稳定段 RSS 增加 512 KiB，FD 6→6，退出后无相关进程或缓存。该 CLI 测试不等同于完整界面验收。

## 本轮实际界面与运行时

原生 CUA 现已能够列举、读取、点击和截图，原先约 120 秒的控制超时本轮未再出现。根因尚未证实；不声称重置工具就是确定的修复原因。恢复页只显示过滤后的报告，继续前业务数据库未创建，设置菜单禁用。授权、503 失败重试、发送中撤回和设置页共享关闭状态均已实际核验。

通过界面导入本机原创演示源，实际播放、暂停、暂停时从 00:36 拖到 01:24、恢复播放、切集、进入和退出原生全屏。原创 XML 的 128 条弹幕导入并实际显示。第 2 集 21.75/128 秒历史落盘，正常退出、重开后历史仍在，点击继续观看成功恢复。

在新的隔离目录完成 **3 轮真实合成崩溃→恢复→授权→503/重试→撤回→正常退出**。第一轮的同一 SwiftUI 进程另外完成 **30 轮授权/撤回**：这些额外切换在队列清空后进行，不声称它们触发了 30 次 SDK 发送。预热 3 轮后 RSS 70,640 KiB，第 30 轮 70,752 KiB（+112 KiB），FD 始终 10，采样 CPU 0.0%、线程 4–5；采样时无子进程，队列及缓存为空，业务数据库仍未创建。撤回后接收计数未因空队列循环增加。此证据不证明零泄漏；原型固定 144 字节未定位分配和正式 App 未做完整泄漏普查的限制仍保留。

真实内置 Node 启动原创 Contract A 测试脚本，界面显示它返回的内容。实际 Emulator/Bridge 到达“已就绪”，并与 Node 同时运行。正常退出约 **1.679 秒**，历史、播放器、Node、Android、诊断按序清理；App、Node、私有 ADB、Emulator 四个确定归属的 PID 全部消失。

## 发现及处理

1. 临时符号验收脚本给 Node 重签名时漏了 JIT entitlement，导致 V8 脚本启动前 SIGTRAP。已修改 `prepare-stage7-symbols.py`，仅给内置 Node 应用现有 `NodeHelper.entitlements`，与正式 `package-app.sh` 一致。修正后的 Node 实际启动/正常停止、完整严格签名和 App UUID 不变均已核验。未修改正式产品代码，也没有以此替代最终打包。
2. 内部盘约 8.9 GiB 不足以创建 10 GiB AVD。尝试外置 AVD 链接被验收目录防链接检查正确拒绝，随后已恢复原路径。仅将本任务已经完成的 Stage6Sparkle 夹具移到外置开发盘，逐文件核对 SHA-256 并保留旧路径链接，释放到约 13 GiB 后成功启动。用户原有 SDK 与 Android 数据未迁移。
3. 一次启动中的 `/usr/bin/file -b .../platform-tools/adb` 在 `__open` 等待超过 5 分钟，调用方停在 `ExternalAndroidRuntimeValidator.hostCanExecute` 的 `waitUntilExit()`；UI 仍能交互，但 SDK 状态未更新。同一命令从 shell 执行成功。保存采样后，仅停止该确定归属的检查子进程，重新用界面检查 SDK 和启动成功。**这只证明可恢复，未证明根因解决**，须继续复现/评估检查超时边界。

## 仍须完成

- 真实睡眠/唤醒：用户于 2026-10-13 明确表示暂不方便，保留待验收；不能由逻辑测试替代。
- SDK 文件检查等待问题：保存了 App 和子进程采样，继续定位或加入经验证的有限等待策略后复验。本轮运行时成功及正常退出不消除此风险。
- macOS 12、AirPods/蓝牙遵照“仅当前机器”范围保持 NOT_TESTED。两个未提供的外部 Node Contract B 样本保持未测。

## 续跑与证据

- 结构化结果：`stage8-ui-acceptance.json`；签名修正验证：`stage8-node-signing.json`；汇总：`stage8-progress.json`、`acceptance.json`。
- 原始 UI 树、截图、资源序列、运行时 PID/退出记录、SDK 等待采样和 Node 原创脚本位于忽略目录 `build/stage8-20261013/`。此前自动化和资源证据位于 `build/stage8-20261012/`。
- UI App：`/private/tmp/OKVideoMac-CrashIntegration/Stage8UI/OKVideoMac.app`，当前 Info.plist 指向 `cycles-fixture.json` 中的新恢复循环目录；业务/播放/Android 验收目录仍由同目录 `fixture.json` 记录。更换 fixture root 后需重签外层 App 并验证，保留 Node 的 JIT entitlement。
- 本轮 App、Node、ADB、模拟器和三个本机服务器都已停止。续跑所需服务为原创演示源 9481、本机 503 接收器 9482、原创 Node 夹具 9483。
- 旧 Stage6 夹具归档位置：`/Volumes/XcodeDev/OKVideoMac-CrashIntegration-Stage8-20261013/completed-stage6-artifacts`，移动与哈希核验记录在原始证据中。

第 8 步不得标为全通过，不进入第 9 步最终 Release 打包。
