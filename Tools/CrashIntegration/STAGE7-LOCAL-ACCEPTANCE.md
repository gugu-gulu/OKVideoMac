# 第 7 步：本地符号链路验收记录

日期：2026-10-12。基于第 6 步归档提交 `738a6ae`。这是远端验收前的本地检查记录。后续 Sentry 验收已完成，见 [远端验收记录](STAGE7-REMOTE-ACCEPTANCE.md)。

## 已完成的本地验证

- 普通 Release 与故障验收 Release 各 82 项 XCTest 通过，零失败、零跳过。
- 符号归档的 7 个真实 Mach-O 正反例通过：匹配、禁止覆盖、strip/sign 后保持匹配、篡改 dSYM、版本变化、二进制 UUID 变化、旧 dSYM 误配。
- 两套构建分别保存 dSYM、版本、Build、源码提交与工作文件摘要、arm64 UUID、签名前后产物哈希，未混用符号。
- 普通构建无验收环境字符串或故障注入入口；其中自有 C 函数解析到 `DiagnosticHandlers.c:21`。
- 实际触发 Swift/C 合成崩溃，重启过滤后由匹配 dSYM 在本地 atos 解析到源码行；实际 SDK 请求仅发送至本机 503 接收器，保留同一事件 ID 供后续重试，白名单字段检查通过。Sentry 请求为 0。

- swift：`main (in OKVideoMac) (OKVideoMacEntry.swift:0)`; `specialized static OKVideoMacEntry.main() (in OKVideoMac) (OKVideoMacEntry.swift:25)`; `specialized static CrashAcceptance.runEntryIfRequested(session:) (in OKVideoMac) (CrashAcceptance.swift:115)`; `specialized static CrashAcceptance.faultIfRequested(_:) (in OKVideoMac) (CrashAcceptance.swift:91)`。
- c：`ok_crash_acceptance_fault (in libCrashAcceptanceFixture.dylib) (CrashFixture.c:4)`。

## 待验收产物

独立验收版本：`com.okvideomac.OKVideoMac@0.8.4+1377001`；环境：`okvideomac-crash-integration-acceptance`。普通构建保留 0.8.4 / 137、独立测试 bundle ID，仍不是最终交付包。

| 验收模块 | arm64 UUID | 签名后 SHA-256 |
| --- | --- | --- |
| libCrashAcceptanceFixture.dylib | E35B5921-B68B-3FD2-8308-D96DF20E140D | b3e009b3bc8b6fa4b3bc937220951b262cf4e12c1cd05318b5c77a71056d2f3d |
| OKVideoMacRelauncher | 744A559D-9E94-3A0A-BCFD-8360F68836EA | 1c75d61c9aaea72367850310f587420312e7f76eb3222b84cc8197af9b701956 |
| OKVideoMac | B98A5388-16F7-391C-B618-D641A4721197 | 727b7d278c1129e16d8e43cc1d25b58f20116301b5cfd48b3a03a450634566f2 |

持久本地归档：`Tools/CrashIntegration/build/stage7-20261012/`（Git 忽略目录）。包含两套 App、各自 dSYM 和机器可读清单。复跑工具为 `prepare-stage7-symbols.py`、`test-stage7-symbolication.py`、`test-symbol-archive.py`；临时崩溃状态路径在 `stage7-local-symbolication.json` 中。

打包脚本现已接入剥离前归档、最终 bundle UUID/哈希复核，并在依赖复制完成后重新生成镜像地址清单。只验证了这些独立检查及脚本语法，完整 `package-app.sh` 流程按原计划留到第 9 步，不把本地验收 App 当成交付包。

## 原生符号缺口

下列现有二进制未找到同 UUID 的 dSYM，保留为缺口；未重编另一套库冒充匹配符号。此处列的是本轮验收 App 的完整镜像清单，最终打包时新增的 FFmpeg 等依赖仍须另行登记。

- `Contents/Frameworks/CrashReporter.framework/Versions/A/CrashReporter`
- `Contents/Frameworks/Sentry.framework/Versions/A/Sentry`
- `Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate`
- `Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle`
- `Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater`
- `Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader`
- `Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer`
- `Contents/Frameworks/libOKMPVBridge.dylib`
- `Contents/Frameworks/libOKQuickJS.dylib`
- `Contents/Frameworks/libmpv.dylib`
- `Contents/Resources/NodeRuntime/node`

## 当时的待办（已由后续远端验收完成）

上个聊天的自动审批拒绝读取现有 Sentry 登录会话，理由是未识别到当前账号会话的明确授权。本轮尚未重试该操作，也没有上传符号、登记版本或发送外部事件。

待明确授权的操作：访问现有私有 `okvideo/okvideomac-macos` 项目会话；上传本验收构建的 App、重启助手及 C 合成故障库三个 dSYM（含函数名、文件/构建路径和行号，不含源码包）；登记上述验收版本；发送两份白名单合成 Swift/C 崩溃并核对后台源码行、UUID、失败重试和撤回后零发送。原型 0.1.2 的授权与符号不冒充本次正式接入构建的验收。

桌面 App、公开更新源和 GitHub 发布未修改。macOS 12 与 AirPods/蓝牙仍按用户要求标为 NOT_TESTED；原型固定 144 字节已知泄漏不因本轮符号测试而消除。
