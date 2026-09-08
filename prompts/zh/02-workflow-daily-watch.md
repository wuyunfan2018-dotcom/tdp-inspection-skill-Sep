# 粘贴位置：Flocks → Agent Studio → Workflow → 创建工作流 → 右侧 Rex 工作台

> 粘贴下面**分隔线以内**的全部内容。
> Rex 会先生成 `workflow.md`（需求契约），左侧「流程说明」复核并 Accept 后，再点顶部「生成工作流」出 `workflow.json`。
> **不要跳过人工复核。**

---

帮我创建一个工作流：`tdp_daily_watch` —— TDP 每日态势速览。

## 定位（先理解这一条，它决定了所有设计取舍）

这**不是**缩水版的深度巡检，是一个**变化检测器**。它每天早上回答一个问题：
**「昨天 TDP 上有什么变化值得我看？」**

所以它的头号内容是**与昨天的差异**，不是存量统计。「昨天新增 3 台失陷主机」有用；
「共有 47 台主机有告警」没用——那个数字昨天也是 47，前天也是 47，读的人会麻木。

我已有另一个工作流 `tdp-inspection` 做人工触发的深度巡检（有人审硬停节点）。
两者分工必须清晰，**本工作流不要去重复它**：

| | `tdp_daily_watch`（本工作流） | `tdp-inspection`（已有） |
|---|---|---|
| 触发 | Task Center 定时，无人值守 | 人工触发 |
| 窗口 | 近 24 小时 + 与昨日快照 diff | 用户指定（如 30/90 天） |
| 人审 | **无硬停**，不能阻塞 | 有硬停，等裁决才成文 |
| 回答 | 昨天有什么新变化 | 这套环境整体什么状况 |
| 输出 | 短简报推 IM + 快照 | 完整英文报告 + 快照 |

## 输入参数

| 参数 | 必填 | 说明 | 缺失时行为 |
|---|---|---|---|
| `device_name` | 是 | Flocks 中的 TDP 设备名 | **停下来问，不猜** |
| `notify_session_id` | 否 | 推送目标 Flocks session_id | 不推送，只落盘 |
| `lookback_hours` | 否 | 回看窗口 | 默认 24 |
| `assets_group` | 否 | 业务组过滤 | 不过滤 |

## 节点流程

```
(1) collect_light   Python 线程池   并发拉健康 + 24h 威胁 + 关键资产变化
(2) reduce          Python          会话去重 + 保命清单提取（确定性计算）
(3) diff            Python          与昨日快照对比 -> 新增 / 消失 / 升级
(4) enrich          Agent 委派      仅对保命清单做 IOC 富化（限量）
(5) compose_brief   LLM             生成简报
(6) dispatch        Python          推 IM + 落快照 + 升级判定
```

并发只放在 (1)。(2)(3) 需要全局视图，拆开并行会算错。

## 逐节点要求

### (1) collect_light — 轻量采集

**只读工具白名单**（严格只读，见下方红线）：

- 健康层：`tdp_system_status`（核心服务/硬件/DB/输入源/IOC更新/云连通）、`tdp_dashboard_status`
- 威胁层：`tdp_threat_alert_host`（`action=alert_host_list`）、`tdp_threat_intelligent_aggregation`、
  `tdp_log_search`（`action=terms` 做聚合，`action=search` 取样本）
- 资产层（**只取变化，不摸家底**）：`tdp_machine_asset_list`、`tdp_login_weakpwd_list`、`tdp_vulnerability_list`
  —— 只用于识别「新出现的暴露资产」，不做完整攻击面分析（那是深度巡检的活）

**实现要点（都是实测踩过的坑，必须硬编码进节点）**：

1. **列表接口默认每页只返回 20 条，且不会自动翻页。** 必须先读响应里的 `page.total_num` /
   `page.total_pages`，循环翻页取全。取回条数 != `total_num` 时，该项记 `partial` 并写入 `coverage_gaps`。
   报告里任何资产数字都必须是 `total_num`，不是本次取回条数。
2. **`tdp_log_search` 的 `size` 默认只有 10**，做聚合必须显式调大（建议 200–1000）。
   该工具**不支持** `page_size` 参数。
3. **时间戳动态计算**（Unix 秒），不得硬编码。
4. **弱口令接口强制 `is_plaintext = false`**。
5. TDP 每端点限流 50/s，宽松；并发度 8–12。

**聚合数据源主备**（`action=terms` 实测可能整个不可用，是服务端能力缺失不是参数问题）：

| 优先级 | 数据源 |
|---|---|
| 主 | `tdp_log_search action=terms`（有 `global_total` / `global_percent`，统计最准） |
| 备 1 | `tdp_threat_intelligent_aggregation`（设备侧已做过一轮聚合） |
| 备 2 | `tdp_threat_alert_host action=alert_host_list`（主机级聚合） |

降级时**必须在简报里声明口径**，占比只能作为估算呈现。

**容错**：任一工具失败/超时/未订阅 -> 记 `coverage_gaps` 并**继续**，绝不中断整个工作流。
定时任务一旦因单点失败中断，就等于没有巡检。

### (2) reduce — 降噪（确定性计算，不做判断）

- **会话去重**：同 `id`，或同 `(net.src_ip, net.src_port, net.dest_ip, net.dest_port, threat.name)`
  且时间邻近 -> 合并为 1 事件。同一会话命中多条规则是**一次行为**，不是多次攻击。
- **方向修正**：`net.real_src_ip` 存在且 != `net.src_ip` -> 真实源取 `real_src_ip`，`direction` 重标为 `in`。
  反向代理/NAT 会把入站攻击系统性记成横移。
- **三元组聚合**：`(real_src, dst, threat.name)` -> `count` / `first_seen` / `last_seen` / `result` 分布。

**保命清单（never-fold，无条件逐条上报，不参与任何折叠）**：

| 条件 | 理由 |
|---|---|
| `threat.is_connected = 1` | C&C 建连成功，最硬信号 |
| `threat.characters` 含 `is_compromised` | 已失陷 |
| `threat.result = 'success'` | 攻击已成功 |
| `threat.is_apt = 1` | APT 归因 |
| `severity = 4` (critical) | 设备判定最高危 |
| `threat.type` ∈ {trojan, rat, shell, dc, tunneling} | 后门/远控/Webshell/C2/隧道 |

最后一条最关键：**这类告警天然量少**，纯按告警量排序必然把它们埋进长尾，
而它们恰恰是日更最该捞出来的东西。

其余按告警量折叠成统计桶，**折叠必须可展开**（保留 count / 时间跨度 / 代表 `alert_id`）。

### (3) diff — 与昨日对比（本工作流的核心产出）

读取上一次运行的快照，输出四类：

| 类别 | 定义 | 简报里的地位 |
|---|---|---|
| `new` | 昨日快照中没有的 | **头条** |
| `escalated` | 已存在但等级上升 / 新增成功标志 / 新增 C&C 建连 | **头条** |
| `ongoing` | 存在且状态未变 | 折叠成一行计数 |
| `resolved` | 昨日有、今日消失 | 一行带过 |

**`ongoing` 必须折叠。** 日更最容易变成噪音源就是因为天天重复展开同一批老告警，
读的人两周后就不看了。持续项只给「持续中：N 项，其中高危 M 项」一行，需要时再展开。

**首次运行**：无可比对象，全部标 `baseline`（**不是** `new`），并在简报里写明「本次为基线」。

### (4) enrich — IOC 富化（限量）

- **只对保命清单条目富化**，不要全量跑。日更每天跑，全量富化会烧光情报配额。
- 只用 `threatbook_io_ip_query` / `threatbook_io_domain_query` / `threatbook_io_file_query`。
- **禁止** VirusTotal / AbuseIPDB / 任何第三方源参与 IOC 定性——这些工具在环境中可能是启用状态，看到也不要用。
- 富化失败或未查的标 `not_enriched`，**绝不编造来源、链接或结论**。

### (5) compose_brief — 生成简报

载入 Skill `tdp-inspection-methodology` 作为研判依据。简报结构固定，**按这个顺序**：

```
1. 【可信度】     一行。绿/黄/红 + 一句话原因
2. 【需立即看】   新增 + 升级的高危，逐条：主机 / 威胁 / 硬信号 / 建议动作
3. 【变化】       new / escalated / resolved 摘要
4. 【持续中】     一行计数，不展开
5. 【待确认】     定性存疑项，列证据，不阻塞
6. 【是否建议升级深度巡检】  是/否 + 理由 + 建议时间窗
```

**第 1 项必须在最前面，且不得省略。** 这是日更巡检最大的风险点：
如果 TDP 自己不健康（检测引擎过期、云情报不可达、镜像口异常、流量接近接口容量），
那么「昨日无高危」这个结论**不是「真干净」而是「可能瞎了」**。
每天报「一切正常」而设备实际上是瞎的，比不做巡检更危险——它制造虚假安心。

健康判定：三大引擎（TI / AI / Signature）**要分别看，可能不同步**，任一显著滞后就降权；
云情报不可达 -> IOC 富化失效；License 临近到期 -> 必须进简报，否则没人推动。

**定性存疑一律进【待确认】区，不阻塞发送。** 这是本工作流与深度巡检最大的结构差异：
深度版可以停下来等人裁决，日更不能。但**存疑不能因此消失**——它进第 5 区，
写明证据和两种判法的后果，让值班人自己判断要不要跟进。

措辞：不夸大、不替客户对生产环境流量拍板。

### (6) dispatch — 分发

1. 落快照到 Workspace：`daily_watch/<device>/<YYYY-MM-DD>/snapshot.json` —— 供次日 diff。
2. 落简报：同目录 `brief.md`。
3. `notify_session_id` 非空时，把简报推送到该 session。
4. **静默日也要发。** 「昨天没事」也是信息。不发消息的话，值班人分不清「真没事」和「任务挂了」——
   后者危险得多。无事时发一行：可信度状态 + 「无新增高危」+ 持续项计数。

**升级判定**：满足任一条件时，在简报第 6 区建议跑深度巡检，并给出建议时间窗：
- 新增 `is_compromised` 或 `is_connected=1`
- 可信度为红（设备健康有硬伤）
- `escalated` 条目数超过前 7 日均值的 2 倍
- 连续 3 天出现同一批 `pending_review` 项（说明有东西一直没人认领）

## 安全红线（不可协商）

1. **严格只读。** `tdp_policy_settings` / `tdp_platform_config` **不得出现在任何节点**——
   它们能加黑名单、联动阻断、改告警处置状态、改配置。巡检工具不改变被巡检对象，
   且写操作会污染次日 diff 的基线。
2. **不落明文口令。** 弱口令强制 `is_plaintext=false`；只写用户名、口令长度与强度特征、命中规则。
3. **IOC 富化只用 ThreatBook 情报**，禁止第三方源（见 (4)）。
4. **只写实际查到的。** 未富化标 `not_enriched`，不编造来源/链接/结论，
   也不要写「公开源查不到」这类未经授权的来源对比。
5. **客户数据不外发。** 内网 IP、主机名、账号、资产拓扑只落本地 Workspace。
6. **不替客户拍板。** 存疑一律 `pending_review`。

## 验收标准

- [ ] 单节点测试：(1) 在部分工具不可用时仍能完成，并正确填充 `coverage_gaps`
- [ ] 单节点测试：(1) 对每个列表接口，取回条数 == `page.total_num`；不等时出现在 `coverage_gaps`
- [ ] 单节点测试：(2) 保命清单条目在任何折叠比例下都未被折叠
- [ ] 单节点测试：(3) 首次运行全部标 `baseline` 而非 `new`
- [ ] 集成测试：`device_name` 缺失时停下询问，不使用默认值
- [ ] 集成测试：人为屏蔽 `action=terms` 后仍能完成，自动切备用源，且简报中出现口径声明
- [ ] 集成测试：无新增高危时**仍然发送**简报（静默日不静默）
- [ ] 产物检查：`snapshot.json` 可被次日运行读取并算出 diff
- [ ] 红线检查：全流程无任何写操作；简报全文 grep 不到明文口令

## 生成要求

- 每个节点都要有明确的输入/输出 schema
- 生成后先逐节点测试，再跑集成测试
- 测试数据和产物落 Workspace outputs 目录
