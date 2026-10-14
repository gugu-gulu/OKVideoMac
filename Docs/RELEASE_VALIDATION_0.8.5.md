# OKVideoMac 0.8.5（Build 138）正式发布验证记录

日期：2026-10-14。GitHub Release：[v0.8.5](https://github.com/yaolin-dev/OKVideoMac/releases/tag/v0.8.5)，非 Draft、非 Prerelease、latest。已安装并打开桌面版本供用户测试。

## 不可变身份与实现

- exact release commit：`b7fd9026bfee95d2d815dbb39e985225c3004e67`，从干净 main 经 `package-app.sh --mode distribution --notarize` 重新构建；annotated tag `v0.8.5` 固定同一提交。
- App 0.8.5（138），Android Bridge 0.3.48（60）；arm64 / 最低 macOS 12.0；构建主机 macOS 14.8.9、Xcode 16.2 / SDK 15.2。商业工作树未参与构建。
- 新增本机过滤后的崩溃捕获/恢复、诊断控制及协同退出；SDK 文件架构检查 2 秒截止与有限清理。恢复门禁保留 WindowGroup 原生创建动作，修复关闭所有浏览窗口后无法重开的回归。
- 相比公开 v0.8.4，包含 `ca0a16997acbc42e2b99af238c204a4fffadc98e` 的弹幕渲染改进：保留文字填充/颜色，柔和黑色阴影替代描边，普通屏与 Retina 屏保持同一阴影逻辑大小。原发布说明遗漏，见[发布后补充](RELEASE_NOTES_0.8.5_ADDENDUM.md)；普通视频字幕轨道未新增改动。
- 正式包 `OKCrashReportDSN` 为空，不上传崩溃报告。未向 Sentry 上传本次最终 UUID 的符号或新事件；旧验收 Build1377001 后台证据不代表本包。

## 本轮验证

| 项目 | 结果 |
| --- | --- |
| 完整 Release XCTest | 1287 通过、0 失败、17 条件跳过；共 1304 |
| 弹幕文字栅格 | 完整 Release XCTest 内 4 项全部通过：中英文填充、彩色填充、1x/2x 阴影范围、阴影边距 |
| 菜单/真实窗口定向 | 16 通过、0 失败、0 跳过 |
| 静态 SDK 许可证/SBOM 回归 | 6 通过 |
| Android Bridge Release | assembleRelease 与既有签名身份验证通过；未把历史 JVM 全套测试当作重跑 |
| Hardened Runtime | 最终代码/依赖的隔离身份副本：QuickJS、MPV/FFmpeg、Node/V8 JIT 与 5 秒 App 启动通过；以 SIGTERM 结束，只证明该烟测范围 |
| 桌面安装 | 文件字节、链接与执行位匹配，独立 staple、strict/deep、Gatekeeper 通过；旧入口和 App 目标均保留 |
| 正式身份启动 | 现有用户配置、实际安装路径；首次屏幕窗口 1.320 秒，持续观察 20.4 秒，进程留给用户使用；未操作播放或设置 |
| 公开资产 | 16 项本地 SHA-256、GitHub digest、匿名下载逐项一致；latest feed 字节、DMG 与 XML EdDSA 签名通过 |

首轮完整测试中，3 项截图测试缺少历史输出目录，另有窗口关闭后无法重开的真实回归。截图测试现在自行创建目录，窗口动作恢复原生场景工厂。复验另发现菜单监听误作用于夹具菜单和 Android 并发测试提前放开启动等待；已限制为应用主菜单，并等待全部 10 个调用进入测试屏障，保留原次数和窗口断言。最终完整测试无失败；原始失败日志保留。17 项跳过涉及显式 AVD、长时播放、外部样本/可见渲染等条件，未计为通过。

首次正式包在源码敏感信息门禁因两份历史验收 JSON 的本机路径停止。公开快照改用路径占位符，本地原始记录保留；重新从上述新 main commit 完成全部流程。未放宽扫描或签名门禁。

## 签名、公证与符号

- Developer ID Application: Yao Lin (KGG363ABK9)，36 个 Mach-O 的架构、secure timestamp、Hardened Runtime、entitlements、依赖闭包和签名验证通过。
- Apple Notarization **Accepted**，submission `c2186e45-a3b1-4033-9cdc-dab09acc0801`；Apple log 无 issues。最终 DMG staple、Gatekeeper、只读盘内布局、版本、source index、APK 与 SBOM 检查通过。
- DMG SHA-256：`6b669d0cfd9d77bfcafafe3994193c3e8cd940b353595ba7b7b39d8f6bd0a8b8`。稳定 feed / 公钥沿用既有配置，Build 138 高于 137，固定下载 URL 指向 v0.8.5。
- App dSYM UUID `48EC1DB9-FE7E-3ED0-B34A-428BD2DAAD1C`；重启助手 dSYM UUID `C7A44C75-9544-3096-8713-AAF0031D9070`，与最终二进制匹配。36 个 image 记录完整；既有 34 个缺 dSYM 记录含 32 个原生代码 image 与 2 个无代码的静态 SDK 隐私资源 stub，不声明完整第三方源码行覆盖。
- 桌面入口：`Desktop/OKVideoMac.app`；安装目标 `Applications/OKVideoMac-0.8.5-build138.app`。旧入口备份在 `Desktop/OKVideoMac-backups/OKVideoMac-0.8.4-build137-20261014-011425.app`，原旧 App 目标保留。
- v0.8.4 的 Release ID、16 个资产 ID/大小/digest 保持不变；旧 tag 与已发布资产不移动。

## 公开文件 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `OKVideoMac-0.8.5-AndroidDexBridge-release.apk` | `08d8d8dfdb704baac6ef83c5d392f1642ff3c25baf84cc539fce0c4d9e165b9c` |
| `OKVideoMac-0.8.5-build138-SHA256SUMS` | `684e8c81123779620a63855c9a7e30e5cca0f867ebba3f4561828dc21e0f047b` |
| `OKVideoMac-0.8.5-build138-SOURCE_RELEASE_INDEX.json` | `59c741f4058bd5369e01abf409cb2f0532e6117755fe287315602b2bc3fdb0f4` |
| `OKVideoMac-0.8.5-build138-SOURCE_RELEASE_MANIFEST.json` | `af986e0fa4d8487c681eeb2173542fc04c53335276789346d319297a08255a9b` |
| `OKVideoMac-0.8.5-build138-licenses.tar.gz` | `1cefb188fbd0e82ab1f3ff71785e486f4c79cb03af11aa8e13e27ad03078c0dd` |
| `OKVideoMac-0.8.5-build138-source.tar.gz` | `56fe0680fdb7a5b6c3a63d8bf92ea1839642f7b24729638c1a3347b99619e7ac` |
| `OKVideoMac-0.8.5-build138-third-party-source.tar.gz` | `832644b7148c682ebf5b1b78b762cc53a1fd2c92677d6455f718fb98dbbe813a` |
| `OKVideoMac-0.8.5.dmg` | `6b669d0cfd9d77bfcafafe3994193c3e8cd940b353595ba7b7b39d8f6bd0a8b8` |
| `OKVideoMac-0.8.5.dmg.sha256` | `b9fb75034f332028af385d5ac7a02845c3811bd33c1dc731659f15315bd769da` |
| `OKVideoMac-Android.cdx.json` | `26a37147092bd30d3f624bba49052ead75031f70230da02240088442790265d1` |
| `OKVideoMac-Android.spdx.json` | `c1b208975d117b2e2b44e2765ba5502e22dab1981ab23285fb3d06858fe67bb0` |
| `OKVideoMac-macOS.cdx.json` | `e16b4592845dc45bac14075ee6d3efdbe1d58762d931a096b0d394dbbdcdf66f` |
| `OKVideoMac-macOS.spdx.json` | `87e34c3f69750650d1468f46f8895ae3a56c793a759a11740ddb5797875a1096` |
| `RELEASE_NOTES_0.8.5.md` | `3aa48a5d2445d011985c8778ca698fc270c495920cb775b03309d58f5b6c4e77` |
| `THIRD_PARTY_NOTICES.md` | `dcdd1f229b1b8f47f757b6f234bf7394f41667d39991294ba0be0a769c77f54b` |
| `appcast.xml` | `9af0caeeb15f860ec59cd6b2715bbeebabfa861852242a5613a0fb40659c9dcf` |

匿名大文件直连曾超时，改用本机已配置的 localhost 代理通道后完成复核；curl 保留 TLS 校验，无认证头或浏览器 Cookie，系统网络设置未修改。

最终符号、签名产物、完整 Release xcresult、日志与私有原始证据保留在 `Tools/CrashIntegration/build/release-0.8.5-20261014/`（Git 忽略，不作为公开资产）。

## 覆盖边界

本次没有重做真实睡眠/唤醒、macOS 12 或 macOS 27、蓝牙/耳机、两个未提供的外部 Node Contract B 样本、连续深睡/耗电、完整泄漏普查或更新安装端到端测试。此前当前机器的播放/暂停睡眠唤醒证据仍按原范围保留。此前临时副本一次 20 秒未见窗口的原始根因未证实；本次正式启动观察通过，不把它当作原异常根因修复证明。

原生源可复现性例外（原始 zlib 归档及历史 MacPorts 编译器输入）继续公开记录。发布后的文档更新不改变 tag、签名资产、构建时源码和 notes 快照。
