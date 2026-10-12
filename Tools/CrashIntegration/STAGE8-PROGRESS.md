# 第 8 步检查点：自动化及资源通过，实际界面验收未完成

2026-10-12，macOS 14.8.9 / arm64。阶段状态 **PARTIAL_BLOCKED_UI_TOOL**，第 9 步尚未开始。本记录不是最终验收通过证明。

## 已完成

三个 Release XCTest 运行覆盖 **420 个不同测试**，零失败。首轮 401 通过、5 跳过；补跑实际 OpenGL/全屏/长关键帧拖动的 3 项（连同重复基线合计 47）全部通过；另补跑 16 个 Android 生命周期场景（连同重复基线合计 60）。只剩两个外部 Node Contract B 样本测试未运行；不将其计为通过。

原生全屏实际进入/退出 3 轮，渲染恢复及 backing pixel 大小断言通过。本机本轮没有捕获到共享动画采样，因此不宣称动画采样指标通过。长关键帧视频为仓库原创风景图生成的 40 秒夹具，验证播放中、暂停时和连续拖动后状态恢复及尾部事件。

5 次开启捕获的隔离 Release 启动沿用第 1 步相同的被动窗口计数和进程采样方法。首窗中位数 0.362 秒（阈值 0.734 秒）；空闲 RSS 90,336 KiB（阈值 105,216）、CPU 0.0%（阈值 2.2%）、线程 9（阈值 9）、FD 16（阈值 19）、子进程 0。全部达到原固定阈值。测试进程的信号清理不计为正常退出验收；正常退出和真实签名 Sparkle 更新见第 6 步。

同一实际 Release 上传适配器连续尝试 30 次本机 503，全部返回 pending，ID/待发送记录保留。主线程最大间隔 13.5 ms；适配器前后 FD 均为 6；稳定段 RSS 从 24,736 到 25,248 KiB（+512 KiB），峰值 25,264 KiB，最多 6 个线程、1 个上传子进程，结束后相关进程为 0、缓存不存在。撤回后 consent=false、pending=0。该测试没有初始化 SwiftUI/业务，不能代替完整 App 内反复点击恢复/授权/撤回的资源验收，也不能证明零泄漏。原型固定 144 字节未定位泄漏保留。

## 阻塞与未完成

本机界面工具两次读取隔离 App 均约 120 秒超时，应用列表也超时并重置。工具确实启动了测试 App，但没有返回窗口树，未记录实际窗口操作。已清理本轮确切的测试 App 进程和两个本机服务器。

恢复界面控制后仍须完成：完整 App 的配置导入、播放/拖动、窗口/全屏切换与历史保存；恢复、授权、失败重试、撤回循环的实际界面及资源观察；睡眠唤醒与活动 Node/Android 生命周期的剩余实机检查。当前只通过相应逻辑/生命周期回归和独立原生渲染测试。macOS 12、AirPods/蓝牙遵照用户要求保持 NOT_TESTED。

## 续跑位置

- 实现提交 `59e8a80`；Sentry 完整验收提交 `ba1f2c5`。
- `stage8-progress.json`、三个摘要、启动资源和重试资源为跟踪证据。完整树/日志/视频/隔离 UI App 在忽略目录 `build/stage8-20261012/`。
- 临时 UI App：`/private/tmp/OKVideoMac-CrashIntegration/Stage8UI/OKVideoMac.app`；对应数据目录在同目录 `fixture.json`。该 App 内嵌本机 503 DSN，仅为验收产物。
- 本机源命令：`python3 Docs/DemoSource/demo_server.py --port 9481`；本机故障接收器：`python3 Tools/CrashIntegration/stage8-loopback.py`。先确认无同身份验收 App 正在运行再进行压力测试；否则单实例门禁会正确阻止它。
- 外部 Node 样本未测：NodeBundleCompatibilityTests/testRealContractBCompanionConfigurationFromEnvironment(), NodeBundleCompatibilityTests/testRealContractBSamplesFromEnvironment()。

不得把本检查点标为第 8 步 PASS，不进入第 9 步。桌面 App、公开更新、GitHub 发布均未修改。
