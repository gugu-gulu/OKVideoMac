# 第 9 步：本地 Release 包验证通过，保留运行时限制

2026-10-13，macOS 14.8.9 / arm64。状态 **PASS_LOCAL_RELEASE_ARTIFACT_GATES_WITH_DOCUMENTED_RUNTIME_LIMITS**。完整 `package-app.sh` 已成功生成并核验 Release 0.8.4 / Build 137，构建源码为干净提交 `18a127e17c3f2735f3b44c1651824d295684999d`。此后的验收记录提交不改变已构建源码。未替换桌面 App、未推送、未发布、未公证。

## 本地包与验证范围

- [App](build/stage9-20261013/Artifacts/OKVideoMac.app)、[ZIP](build/stage9-20261013/Artifacts/OKVideoMac-0.8.4-macOS-arm64.zip)、[DMG](build/stage9-20261013/Artifacts/OKVideoMac-0.8.4.dmg) 保存在本 worktree 的忽略目录，不是 Debug 产物。
- [源码、许可证、SBOM 与校验和](build/stage9-20261013/Artifacts/SourceRelease/) 和 [最终 dSYM 归档](build/stage9-20261013/Artifacts/CrashSymbols.GYjjw3/) 一并保存。原临时 Artifacts 路径保留链接，使已记录的验证路径仍可访问。
- 完整脚本、独立 App 和重新解包 ZIP 的 bundle 边界、严格签名、架构、RPATH、资源与清单验证通过；DMG 经脚本挂载核验通过。36 个 Mach-O 使用本地 ad-hoc Hardened Runtime 签名。未运行公证和 Gatekeeper 公共发行验收。
- 最终 App 没有合成故障入口、验收目录入口、XCTest 包或内置 dSYM；Sentry DSN 为空。本轮没有新增外部报告、符号或源码上传。
- Android Bridge APK 使用此前已验证且未变的输入，跳过重建；本轮没有 Android 源码修改，不称其为重新编译的 APK。

| 文件 | SHA-256 |
| --- | --- |
| App 主程序 | `01497d07d4e035dd09b653438eda05986e65e14f611b32cab7ccc1d4d5662213` |
| ZIP | `8067e23a4ec13ec842afb06baa3b2abd0729dda5bb46f04c14eb1bb7a5230262` |
| DMG | `7e8b187a7786bad1499c3472b40c8d1faa38a9e4dea63b811252620a3fac9bd7` |

## 打包前发现的问题及修正

原 SBOM 只列物理镜像，遗漏静态链接的 PLCrashReporter 和 Sentry。已补齐两 SDK 的固定版本、上游提交、源码归档 SHA-256、完整许可证和逻辑 SBOM 记录；SPDX/CycloneDX 现有 36 个物理镜像和 2 个静态 SDK，Android 保持 170 个 Maven 模块。6 个清单回归包含遗漏、重复、错误版本、缺失/被篡改许可证和哈希边界检查，均通过。SDK 资源许可证与精确上游归档逐字节一致；未修改上游源码，不宣称官方 Sentry 二进制可逐位重建。

两个新聚合许可证最初为只读，导致打包的 xattr 清理失败。仅修正这两文件的工作区权限，字节不变，实测 xattr 操作通过。第一次权限探针的临时目标也只读，已保存该夹具失败及后续修正记录。

Xcode 为静态 SDK 的隐私清单生成无代码的 framework 资源桩。实测两者 `__text` 为 0、无全局定义，App 已静态包含 SDK 类且没有动态加载引用。保留 PrivacyInfo.xcprivacy 与资源容器，严格拒绝意外代码/依赖/缺失隐私文件，再把临时构建 install name 改为相应 `@rpath`。真实桩正例及“含代码”“缺失隐私”反例通过，隐私文件和 App 主程序字节不变。新增明确的桩文件及 framework 容器由内到外签名；两个容器严格签名和 Hardened Runtime 验证通过，随后完整打包成功。失败的前置打包日志和符号归档另存，未把失败包计为通过。

## 最终符号范围

最终主程序 UUID 为 `115A9AD6-418B-3E68-96A6-4B675B793094`，App 和 Relauncher 所需 dSYM 与最终镜像 UUID 精确匹配。36 个镜像均登记 UUID 和哈希；其余 34 个没有匹配 dSYM，其中 2 个是零代码资源桩，32 个是原生代码镜像。详细缺口见结构化结果，不能宣称所有依赖支持源码行解析。

第 7 步 Sentry 后台证明属于验收 Build 1377001 的旧 UUID，不能作为本次 Build 137 的后台证明。本次最终 UUID 仅在本地验证，未新增 Sentry 上传或事件。

## 实际界面烟测及限制

从严格验证通过的最终 App 制作临时副本，只更改 bundle ID、重建镜像身份元数据并重签外层；编译代码 UUID 保持一致。通过临时 Foundation home 和独立 bundle ID 隔离业务文件、偏好；没有 XCTest 标志或验收根目录入口。正式身份包保持不变，因此这项烟测没有覆盖正式 bundle ID 的运行时准入。

首次启动在 20.048912 秒内未看到窗口，0600 捕获文件已存在；根因未证实。首轮结果/日志被重试覆盖，仅能从当时工具结果重建记录，不冒称独立原始日志仍在。第二次同副本首窗为 0.623695 秒；随后两个全新业务目录为 0.505719 秒和 0.277609 秒，均启用真实捕获并创建 0600 文件。这两次只是额外首窗复查，不替代第 8 步已有的五轮固定资源门槛，也不称为冷缓存测试。

第二次实际通过界面导入原创 loopback 演示源，显示 1 个站点和 12 部内容。第 1 集自然结束后自动进入第 2 集；实测渲染画面，时间从 01:24 前进到 01:38，空格暂停成功。高级设置显示 0.8.4 (137)、崩溃共享关闭、过滤报告 0。历史 UI 与 SQLite 均保存第 2 集 98.41666666666667/128 秒。原生 Command-Q 返回成功，退出码 0，确定 PID 38727 消失，退出前无子进程，退出后历史精确不变、报告队列/上传缓存为空。mpv 在切集/关闭播放器主动释放渲染上下文时记录 video output initialization failed，未观察到错误页；不声称运行日志无任何错误文字。最初探针期待“第 2 集”，数据库实际为“第 02 集”，仅修正探针期待，没有改写产品数据。

CUA `getApp` 本轮等待 **1305.3189 秒（约 21 分钟）** 才返回，传入的 15 秒 timeout 未限制这次调用。之后必要的导入、播放、暂停、设置、历史和 Quit 操作可完成。**界面控制等待问题没有解决**，不能以本轮界面通过宣称工具根因已修复；首次首窗异常也仍待解释。

## 睡眠复测及交付边界

第二轮有效复测唤醒后仍暂停，位置精确为 225.41666666666669 秒，与睡前相同；Android 在线、FD 47→47、原有 App/Android 进程不变。第一轮实际自动续播也已通过。互联网共享已恢复为原开启状态，相关测试服务和 App 已退出。睡眠过程中有 USB 后台维护唤醒，连续深睡 30 秒和耗电验收仍未测；macOS 12、AirPods/蓝牙、两个未提供的外部 Node Contract B 样本仍未测。原型 144 字节未定位分配和正式 App 未做完整泄漏普查的限制保持。

桌面主程序 SHA-256 仍为 `5ab593e778d14d084cc4f9b5a83d6875b5479a2a6d98640d318c6f5bf33d06b5`，与本轮前一致。最终原包主程序哈希也未被烟测改变。本地可审阅产物准备完成；公开发行、桌面替换、正式身份烟测和新 UUID 的后台符号核验不在已完成结果内。

结构化结果：[stage9-local-release-acceptance.json](stage9-local-release-acceptance.json)。原始日志、UI 树、截图、符号和校验记录：[build/stage9-20261013/](build/stage9-20261013/)。

## 界面等待与首窗后续排查

当前聊天的授权预检、固定烟测身份及任务内核恢复已验证通过；九次额外启动未复现原 20 秒异常，原始根因仍未证实。详情见 [CONTROL-STARTUP-FOLLOWUP.md](CONTROL-STARTUP-FOLLOWUP.md)。前文保留本步当时观察，不以新的工具流程覆盖原始限制。App 实现和已验证的 Release 包未改变。
