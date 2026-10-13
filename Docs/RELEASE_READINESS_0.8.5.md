# OKVideoMac 0.8.5（Build 138）发布就绪记录

日期：2026-10-14。状态：正式发布准备中；签名、公证、安装与公开资产门禁尚未完成，未作为正式发布通过声明。

基线为 origin/main `3ae794b`，崩溃集成和 SDK 有限等待已经在隔离分支逐步验收。商业工作树不参与本次构建。用户已授权发布新 Release 并替换桌面版本；旧 v0.8.4 资产和 tag 保持不变。

本次版本固定为 0.8.5 / Build 138，Android Bridge 0.3.48 / 60 与原生依赖版本保持。正式包的远程崩溃上传 DSN 为空，本地捕获启用，不新增真实报告上传授权。

正式流程须从干净本地 main exact commit 执行 `package-app.sh --mode distribution --notarize`；Developer ID、Apple Accepted、staple、Gatekeeper、最终 DMG/安装、签名 appcast、源码/许可证/SBOM/哈希全部通过后，才推送 main/tag 并公开资产。桌面版本先备份，再用核验后的 Release 替换。

当前机器既有功能证据及边界见 `Tools/CrashIntegration/acceptance.json` 与 `CONTROL-STARTUP-FOLLOWUP.md`。不把累计 425 个不同测试当作本次全部重跑；本次新测试数字和最终包 UUID 将在实际执行后记录。旧 Build1377001 的 Sentry 后台记录不能证明新 Build138 符号，最终新 UUID 尚未上传后台；原生 dSYM 缺口继续公开记录。

首次首窗异常未复现且根因未证实；macOS12、蓝牙、连续深睡、两个外部 Node ContractB 样本与完整泄漏普查保持未测，不扩大既有保证。

正式发布准备中新发现的窗口重开回归已修复：恢复菜单只拦截执行，保留 SwiftUI 原生 WindowGroup 场景工厂。完整 Release XCTest 最终 1287 通过、0 失败、17 条件跳过（共 1304）；菜单/真实窗口定向 16 通过。截图输出目录与 Android 并发测试入场屏障已修正，保留原始窗口、次数及恢复门禁断言。早期失败记录保留，不计为最终通过。商业源码未参与。

首次正式源码扫描拦住两份历史验收 JSON 的本机绝对路径；已保留本地原始证据，公开记录改用工作树/用户目录占位符，数值、哈希与 UUID 不变。扫描规则未放宽，须重新从新 exact main commit 打包。
