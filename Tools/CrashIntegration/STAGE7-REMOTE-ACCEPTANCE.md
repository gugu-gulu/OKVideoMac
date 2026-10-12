# 第 7 步：Sentry 远端验收通过

日期：2026-10-12；实现提交 `59e8a80`。用户明确授权现有私有 Sentry 项目会话、三个指定 dSYM、独立验收版本及两份合成事件。另获 GitHub 登录授权后，直接发现 Chrome 已登录 Sentry；未新增权限。

- 三个 dSYM 由官方 sentry-cli 上传并等待处理成功，UUID 与本地归档一致；未上传源码包。App、重启助手、C 故障库分别为 `B98A5388-16F7-391C-B618-D641A4721197`、`744A559D-9E94-3A0A-BCFD-8360F68836EA`、`E35B5921-B68B-3FD2-8308-D96DF20E140D`。
- [Swift 事件](https://okvideo.sentry.io/issues/7787794970/events/aa93569f6cea519eb05ce3274d429416/)：后台解析至 `CrashAcceptance.swift:91`、`OKVideoMacEntry.swift:25`，App Debug ID 与 dSYM 一致。
- [C 事件](https://okvideo.sentry.io/issues/7787794966/events/ae7254fa0402a631c23f7334e8d3c938/)：后台解析至 `CrashFixture.c:4`、`CrashAcceptance.swift:89`，C 模块 Debug ID 与 dSYM 一致。
- 两份事件均显示 0.8.4 (1377001)、`okvideomac-crash-integration-acceptance`；附件、回放和用户计数均为零。现有 API 令牌读事件返回 403，因此通过授权网页核对；没有扩大令牌权限。这不是完整后台 JSON 审计。
- 本机 503 失败后保留的两份事件 ID 在实际 Sentry 重试成功时不变，待发送队列归零，缓存删除。
- 撤回后新生成本地 C 事件 `0ae5a527aa3bdf30d5c5cb7c76f9d83d`，状态为 consent=false / pending=1 / localOnly / cacheExists=false；Sentry 同项目全部环境最近 14 天精确搜索无结果。该后台检查为当时观测，结合本地禁止发送结果验证。

机器可读结果为 `stage7-remote-acceptance.json`。网页文本、截图、上传/版本登记日志保存在忽略目录 `build/stage7-20261012/Stage7Acceptance/`；未归档会话或令牌。

第 7 步状态为 **PASS_WITH_DOCUMENTED_NATIVE_GAPS**：已知 11 个原生镜像 dSYM 缺口见本地记录，不能据此宣称所有依赖均支持源码行解析。最终交付 App 及新增依赖的符号核对仍须第 9 步执行。未发布、未推送、未替换桌面 App。继续第 8 步当前机器回归；macOS 12 和 AirPods/蓝牙仍为 NOT_TESTED。
