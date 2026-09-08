# tdp-inspection · TDP (NDR) 巡检工作流

> 这是 **需求契约**（人审用）。确认无误后在 Flocks「创建工作流 → 生成工作流」由 Rex 生成 `workflow.json`，
> 并逐节点测试 + 集成测试。本文件不是机器定义。

---

## 1. 目标

对一台已通过 API 接入的 **ThreatBook TDP（NDR）** 做一次**只读**安全巡检，产出：

- **英文 Markdown 巡检报告**（行动优先结构）
- **结构化 JSON 快照**（供下次巡检做 diff）

面向 **人工触发**（PoV 收尾、周期性安全回顾、客户交流前取数）。不做常态化定时告警——
设备健康的小时级静默监控由另一个轻量 skill 负责，本工作流不与其重叠。

### 与 TDP 自动巡检报告的差别

TDP 自带的导出报告会罗列告警和资产，但 **`Security Recommendations` 一章是空的**（原文：
`(Input by inspectors, ...)`），且不做研判、不做降噪、不做维度间关联。本工作流补的正是这三块。

---

## 2. 输入参数

| 参数 | 必填 | 说明 | 缺失时行为 |
|---|---|---|---|
| `device_name` | 是 | Flocks 中的 TDP 设备名 | **停下来问用户**，不猜 |
| `customer` | 是 | 客户标识，用于输出路径与报告抬头 | 停下来问 |
| `threat_window_days` | 是 | 威胁层时间窗（天），如 30 | 停下来问 |
| `asset_window_days` | 否 | 资产层时间窗（天） | 默认 90 |
| `pov_mode` | 是 | `A` = PoV 期间有我方模拟攻击／样本投放；`B` = 纯真实流量监听 | **停下来问，绝不默认** |
| `assets_group` | 否 | 业务组过滤 | 不过滤 |
| `attack_list` | 否 | PoV 对账用的攻击清单（时间窗／源目标 IP／攻击名） | 跳过对账段 |

> **`pov_mode` 为什么必须问**：它决定「一批整齐的失败 Exploit」该归为「检出能力验证」还是
> 「客户真实环境中的外部扫描」。判错会让整份报告的定性系统性偏掉。详见 Skill 方法论。

---

## 3. 时间窗约定（双窗）

TDP 的资产类接口全部强制 `time_from` / `time_to`，这意味着查到的资产其实是
**「该窗口内在网络上出现过的资产」**。窗口开短，低频资产（季度批处理、备用系统、冷备）会整体消失。

| 层 | 窗口 | 理由 |
|---|---|---|
| 第 0 层 可信度 | 当前时刻 + 近 7 天趋势 | 健康是当下状态 |
| 第 1 层 资产 | `asset_window_days`（长，默认 90） | 目的是把家底摸全 |
| 第 2 层 威胁 | `threat_window_days`（短，用户指定） | 目的是聚焦本期发生了什么 |
| 第 3 层 交叉 | **短窗威胁 × 长窗资产属性** | 「这台有告警的主机是不是暴露资产」——资产属性当然要用最全的认知去判 |

**报告中必须同时印出两个窗口**，任何资产数字都要标注其窗口。

### 「新发现」有两个含义，不得混用

| 字段 | 含义 | 来源 |
|---|---|---|
| `tdp_flagged_new` | TDP 自己标记的 Newly Discovered | 设备口径 |
| `new_since_last_inspection` | 与上次巡检快照 diff 得出 | 本工作流快照 |

首次巡检时 `new_since_last_inspection` 全部标 `baseline`（不是 `new`），报告中说明「本次为基线，无可比对象」。

---

## 4. 节点总览

```
[Start]
  |
(1) collect        Python + 线程池   并发拉取只读工具 -> 原始数据
  |
(2) denoise        Python            会话去重/三元组聚合/方向修正/定型/折叠
  |
(3) profile        Python            资产三切面统计 + 效能指标 + 运营指标
  |
(4) correlate      Python            资产 与 威胁 join -> 处置优先级队列
  |
(5) triage         Agent 委派        载入方法论 Skill，对降噪后事件定性 + IOC 富化
  |
(6) human_review   人工确认节点      硬停：发现清单两栏，等用户裁决
  |
(7) compose        LLM               生成英文报告 + JSON 快照 -> Workspace
```

**并行策略**：并发只放在 (1)。(2)(3)(4) 需要**全局视图**（相对基线、帕累托、两表 join），拆开并行会算错。
(5) 受运行级 LLM 并发预算（1–5）限制，靠 leader/follower 分组减少工作量而非堆并发。

---

## 5. 逐节点定义

### (1) collect — 采集

**职责**：并发调用只读设备工具，取回 0/1/2 层原始数据。**本节点不做任何判断。**

**只读白名单（20 个，硬约束）**

| 层 | 工具 | 用途 |
|---|---|---|
| 0 | `tdp_system_status` | 全部子状态汇总（核心/DB/硬件/服务/输入/IOC更新/云连通/时区） |
| 0·1 | `tdp_dashboard_status` | 概览、阻断信息、安全统计、攻击资产、文件检测、阶段统计 |
| 1 | `tdp_machine_asset_list` | `service_list` / `host_asset_list` / `web_app_frameworks` |
| 1 | `tdp_assets_domain_list` | 域名资产 |
| 1 | `tdp_login_api_list` | 登录入口 `summary` / `category` / `list` |
| 1 | `tdp_login_weakpwd_list` | 弱口令 |
| 1 | `tdp_interface_list` | API 接口清单 |
| 1 | `tdp_interface_risk_list` | API 风险 |
| 1 | `tdp_asset_upload_api` | 上传接口 `summary` / `host_list` / `interface_list` |
| 1 | `tdp_cloud_facilities` | 云服务访问源与实例 |
| 1 | `tdp_privacy_diagram` | 明文敏感信息拓扑 |
| 1 | `tdp_vulnerability_list` | 脆弱性 |
| 2 | `tdp_threat_alert_host` | `alert_host_list` -> `host_threat_list` |
| 2 | `tdp_threat_intelligent_aggregation` | 聚合攻击事件 + 攻击成功/时间线/攻击者 |
| 2 | `tdp_threat_external_attack` | 外部攻击严重性分布 |
| 2·4 | `tdp_log_search` | `action=search` 取证 / `action=terms` 聚合统计 |
| 取证 | `tdp_pcap_download` | 按 `alert_id` + `occ_time` 取报文（**仅高价值事件**） |
| 取证 | `tdp_file_download` | 按哈希取恶意文件（**仅命中样本**） |
| 参考 | `tdp_mdr_alert_list` | MDR 研判结果（若客户订阅） |

**明令禁用**：`tdp_policy_settings`、`tdp_platform_config`。这两个能加黑名单、联动阻断、改告警处置状态、
增删改资产、改自定义规则。**巡检工具不改变被巡检对象**，且写操作会污染下次巡检的 diff 基线。
不进白名单，不在任何节点出现。

**不使用**：`tdp_threat_monitor_list`（查询时间范围硬性 ≤24 小时，巡检需要跨周期数据）。

**实现要点**

- `ThreadPoolExecutor` 并发调用。TDP 每端点限流 **50/s**，宽松；并发度建议 8–12。
- 时间戳必须**动态计算**（Unix 秒），不得硬编码。
- `tdp_log_search` 的 `size` **默认只有 10**，做聚合必须显式调大（建议 200–1000）；**该工具不支持 `page_size`**。
- **弱口令强制 `is_plaintext = false`**（见 §9 安全红线）。

**分页铁律（实测踩过，必须硬编码进节点）**

列表类接口**默认每页只返回 20 条**，且**不会自动翻页**。实测 `service_list` 默认返回 20 条，
而 `page.total_num = 445` —— 只取到 4.5%。若直接把 20 当成资产总数写进报告，整份攻击面分析作废。

节点必须：
1. 每个列表调用先读响应里的 `page.total_num` 与 `page.total_pages`
2. **循环翻页直到取全**（或达到设定上限）
3. **自检**：`len(collected) != total_num` 时，该项记为 `partial`，把实际取到数与总数一并写进 `coverage_gaps`
4. 报告中任何资产数字都必须是 `total_num`，不是本次取回的条数

**聚合数据源主备（实测 terms 可能整个不可用）**

| 优先级 | 数据源 | 说明 |
|---|---|---|
| 主 | `tdp_log_search action=terms` | 有 `global_total` / `global_percent` / `distinct`，统计最准 |
| **备 1** | `tdp_threat_intelligent_aggregation` | TDP 自带的事件智能聚合，相当于设备侧已做过一轮降噪 |
| **备 2** | `tdp_threat_alert_host action=alert_host_list` | 主机级聚合：每主机威胁列表与计数，可支撑主机维度的相对基线 |
| 备 3 | `tdp_log_search action=search` + 节点内客户端聚合 | 受 `size` 限制，只能覆盖头部 |

`terms` 不可用时**必须降级并在报告中声明口径**：信噪比的分母不再是全量精确值，
只能给「基于主机级聚合的估算」，不得当成精确占比呈现。

**容错（关键）**

任一工具失败、超时、或该模块客户未订阅 -> 记为该项 `unavailable` 并**继续**，
**绝不中断整个工作流**。所有 `unavailable` 项汇总进 `coverage_gaps`，直接进入第 0 层可信度声明，
报告中明写「本次未覆盖 X / Y / Z」。

**输出 schema（要点）**

```
{
  "meta": { device, customer, threat_window, asset_window, pov_mode, collected_at },
  "coverage_gaps": [ {tool, action, reason} ],
  "layer0_health": { ... },
  "layer1_assets": { services, hosts, domains, web_apps, login_portals, weak_passwords,
                     apis, api_risks, upload_interfaces, cloud, sensitive_data, vulnerabilities },
  "layer2_threats": { alert_hosts, host_threats, aggregated_incidents, severity_distribution,
                      terms_aggregations, raw_samples }
}
```

---

### (2) denoise — 降噪

**职责**：把「规则命中次数」还原成「值得研判的事件」。**折叠，不删除。**

> 完整规则见 §6。核心原则：**一律用相对基线，不用绝对阈值**；每个折叠桶可展开回原始告警。

**输出 schema（要点）**

```
{
  "events": [ {
      event_key, real_src, dst, threat_name, threat_type, severity,
      count, first_seen, last_seen, result_distribution,
      classification,        // scanner_like | background_scan | suspected_business | normal
      keep_reason,           // never_fold:<原因> | pareto_head | null
      is_folded, folded_count, sample_alert_ids[], evidence_pointer
  } ],
  "folded_buckets": [ ... ],
  "denoise_stats": { raw_alert_total, event_total, fold_ratio, never_fold_count }
}
```

---

### (3) profile — 资产画像与指标

**职责**：纯统计，不做判断。

**资产三切面**（对每一类资产都算）

| 切面 | 定义 |
|---|---|
| 对外暴露 | `Internet-facing` 标记 |
| 新发现 | `tdp_flagged_new` 与 `new_since_last_inspection` 分开算 |
| 带风险 | 弱口令 / 脆弱性 / 敏感数据 / 高危端口 / 未识别服务 |

**第 4 层 检测效能指标**

- 信噪比：`never_fold` + 帕累托头部事件数 ÷ 原始告警总量（用 `tdp_log_search action=terms` 的 `global_total`）
- 噪声来源 TOP N：按 `threat.name` 聚合的 `global_percent`
- 疑似误报候选：`suspected_business` 分类的桶
- 覆盖盲区：`coverage_gaps` + 攻击链各阶段是否都有数据

**第 5 层 运营成熟度指标**

- 处置状态分布：`disposal_status` 1/2/3 占比（未处置比例是关键指标）
- 资产台账完整度：资产名为 `Preset asset` 的主机占比
- 阻断策略使用情况：来自 `tdp_dashboard_status` 的阻断信息（**只读统计，不做任何变更**）

---

### (4) correlate — 交叉关联

**职责**：把第 1 层和第 2 层 join，产出**处置优先级队列**。这是整份巡检最核心的产出。

> 完整规则见 §7。**本节点必须单点执行**——需要两层的全局视图，拆分并行会算错。

**输出**：优先级队列，每条带**两维依据**（资产侧证据 + 威胁侧证据），按 P0/P1/P2 排序。

---

### (5) triage — 研判（Agent 委派）

**职责**：委派专家 Agent，载入 `tdp-inspection-methodology` Skill，对降噪后的事件做定性。

**输入**：`events`（仅 `never_fold` + 帕累托头部）+ `correlation_queue` + `pov_mode` + `coverage_gaps`

**做三件事**

1. **流量定性三分法** —— 每个事件必须落到：`real_threat` / `customer_own_behavior` / `tdp_artifact` / `pending_review`
2. **IOC 富化** —— 仅用 `threatbook_io_ip_query` / `threatbook_io_domain_query` / `threatbook_io_file_query`
3. **家族与归因** —— 从 `threat.name`、`threat.type`、日志 metadata 提取家族特征

**实现要点**

- **leader/follower 分组**：按 `event_key` 分组，每组只研判 leader，follower 复用结论。
  受运行级 LLM 并发预算 1–5 限制，减少工作量比堆并发有效。
- 定性存疑一律标 `pending_review`，**绝不替客户对生产环境流量拍板**。

---

### (6) human_review — 人工确认（硬停）

**职责**：暂停，输出发现清单，等待用户裁决后才继续。

**清单必须分两栏**

| 栏 | 内容 |
|---|---|
| **【需裁决】** | 仅定性存疑项。每条含：结论倾向 / 证据指针 / 两种判法各自的后果 |
| **【客观项】** | 硬信号与统计结果，列出供核对，不阻塞 |

**哪些进【需裁决】栏**（只有两类真正需要人拍板）

1. **扫描器／演练 vs 真实横移** —— `scanner_like` 且涉及内网源
2. **是不是客户自己的工具／行为** —— `suspected_business`、疑似客户自有扫描器／运维隧道／员工软件

**哪些不进**（客观硬信号，直接定稿）：设备健康、License 到期、`threat.is_connected=1`、
`threat.result=success`、`threat.characters` 含 `is_compromised`、弱口令 `result=success`。

用户确认或修正后，把定性结果回写事件，进入 (7)。

---

### (7) compose — 成文

**职责**：生成两份产物落 Workspace。

```
inspection/<customer>/<YYYY-MM-DD>/
  |- report.md        英文巡检报告（结构见 §8）
  |- snapshot.json    结构化快照，供下次 diff
```

报告正文 **英文**；`coverage_gaps` 非空时，**第一页必须出现可信度声明**。

---

## 6. 降噪规则（完整）

### Stage 1 · 归一 Normalize

| 规则 | 实现 |
|---|---|
| 会话去重 | 同 `id`；或同 `(net.src_ip, net.src_port, net.dest_ip, net.dest_port, threat.name)` 且时间邻近 -> 合并为 1 事件。同一会话命中多条规则是**一次行为**，不是多次攻击 |
| **方向修正** | `net.real_src_ip` 存在且 != `net.src_ip` -> 真实源取 `real_src_ip`，`direction` 重标为 `in`。反向代理/NAT 会把入站攻击系统性记成横移 |
| 资产归属 | `src` / `dst` 与第 1 层资产表 join，打 internal/external 标，**覆盖** `src_tag` / `dest_tag`。客户若使用公网地址段做内网，设备会按公网库把它定位成境外攻击者 |
| 回环识别 | 源与目标同为客户自有公网地址 -> 标 `hairpin`（NAT 回环），不计入外部攻击 |

### Stage 2 · 聚合 Aggregate

- 三元组成桶：`(real_src, dst, threat.name)` -> `count` / `first_seen` / `last_seen` / `result` 分布
- 时间规律性：桶内相邻告警间隔的**变异系数 CV**低于阈值 -> 标 `periodic`（计划任务／业务轮询／蠕虫定时行为的共同特征）

### Stage 3 · 定型 Classify（全部相对量）

| 分类 | 判据 |
|---|---|
| `scanner_like` | 单源 `distinct(dst)` > 全网 `distinct(dst)` 中位数 × K **且** `distinct(threat.name)` > M **且** `result` 以 `failed`/`unknown` 为主 |
| `background_scan` | 外部源 + 低频 + `result=failed` + 无后续攻击阶段 |
| `suspected_business` | `periodic` + `result != success` + 目标为自有资产 + HTTP 响应码正常 |
| `normal` | 其余 |

> K、M 作为可调参数暴露在 workflow 配置里，默认 K=5、M=10。
> **绝不写死「打了 100 个目标」「超过 5000 条」这类绝对数字**——换个客户环境立刻失效。

**相对基线的降级路径**：`distinct(dst)` 首选来自 `terms` 聚合；该接口不可用时，
改用 `alert_host_list` 的主机级数据算「每个源主机关联的目标主机数」，中位数同样从该分布取。
两种口径都成立，但**不可混用**，且报告中要标明用的是哪一种。

### Stage 4 · 切分 Split

**保命清单（never-fold，无条件逐条进研判，不参与帕累托切分）**

| 条件 | 理由 |
|---|---|
| `threat.characters` 含 `is_compromised` | 已失陷 |
| `threat.is_connected = 1` | C&C 建连成功，最硬信号 |
| `threat.result = 'success'` | 攻击已成功 |
| `threat.is_apt = 1` | APT 归因 |
| `severity = 4` (critical) | 设备判定最高危 |
| `threat.type` 属于 `{trojan, rat, shell, dc, tunneling}` | 后门／远控／Webshell／C2／隧道 |

> 最后一条最关键：**这类告警天然量少**。纯按告警量做帕累托必然把它们折进长尾，
> 而它们恰恰是巡检最该找的东西。

**其余**：按 `threat.name` 的 `global_percent` 降序累计到 **P%**（默认 80%）的头部进研判，
长尾折叠成统计桶。**所有折叠可展开**，保留 `count` / 时间跨度 / 代表样本 `alert_id` / 证据指针。

> `global_percent` 不可用时，改用备用源的事件计数自行归一化算占比，切分逻辑不变，
> 但**分母是估算值**，须在报告口径说明中写清。

---

## 7. 交叉关联规则（完整）

| 优先级 | 规则 | 条件（均为已采字段） |
|---|---|---|
| **P0** | 准失陷 | 弱口令 `result=success` **且** 该资产 `Internet-facing` |
| **P0** | 已失陷可扩散 | `is_compromised` **且** 该主机自身对外提供服务 |
| **P0** | 暴露面被打穿 | 资产 `Internet-facing` **且** 存在 `threat.result=success` 的告警 |
| **P1** | 影子 IT / 上线即被打 | `new_since_last_inspection` **且** 有告警 |
| **P1** | **监控盲区** | 有告警的 IP **不在**第 1 层资产表中 -> 资产台账缺失 |
| **P1** | 内部跳板 | `direction=lateral` 的源主机 **且** 该主机有对外服务 |
| **P2** | 隐患未被利用 | 资产暴露 + 弱口令/脆弱性，**但无**相关告警 |

每条输出必须带**两维依据**：资产侧（暴露状态／服务／端口／弱口令）+ 威胁侧（威胁名／结果／计数／时间）。
只给一维的条目不进队列。

---

## 8. 报告结构（行动优先）

```
1. Executive Summary
   - 一句话结论
   - 【可信度声明】coverage_gaps 非空时必须出现，明写哪些结论需降权
   - 观测窗口（双窗都要印）

2. Remediation Priority Queue        <- 第 3 层交叉产物，最核心
   P0 / P1 / P2，每条带两维依据 + 建议动作

3. Threat Findings                   <- 第 2 层
   按定性分组：确认威胁 / 客户自有行为 / 统计假象 / 待确认

4. Assets & Attack Surface           <- 第 1 层
   总览 + 三切面（对外暴露 / 新发现 / 带风险）

5. Detection Efficacy & Tuning       <- 第 4 层
   信噪比、噪声来源 TOP N、疑似误报、覆盖盲区、调优建议

6. Operational Maturity              <- 第 5 层
   处置状态分布、资产台账完整度、阻断策略使用

7. Items for Customer Confirmation
   只有客户能认领的事项，逐条列证据与我方倾向

Appendix: 折叠桶统计 / IOC 清单 / 数据口径说明
```

---

## 9. 安全红线（不可协商）

1. **严格只读**。白名单只含 20 个读工具；`tdp_policy_settings` / `tdp_platform_config` 不得出现在任何节点。
2. **不落明文口令**。弱口令接口强制 `is_plaintext = false`；报告只写用户名、口令长度与强度特征、
   命中规则，**绝不写口令内容**。
3. **IOC 富化只用 ThreatBook 情报**（`threatbook_io_*`）。**禁止** VirusTotal、AbuseIPDB 或任何第三方源
   参与 IOC 定性——这些工具在环境中可能是启用状态，必须在节点提示词里显式禁用。
4. **只写实际查到的**。未富化的标 `not_enriched`，不编造来源、链接或结论。
5. **客户数据不外发**。内网 IP、主机名、账号、资产拓扑只落本地 Workspace，不进任何外部查询。
6. **不替客户拍板**。生产环境流量的性质定性存疑时一律 `pending_review`，交人裁决。

---

## 10. 验收标准

- [ ] 单节点测试：(1) 在部分工具不可用时仍能完成并正确填充 `coverage_gaps`
- [ ] 单节点测试：(2) 折叠后可展开回原始告警；保命清单条目在任何折叠比例下都未被折叠
- [ ] 单节点测试：(4) 每条队列条目都带两维依据
- [ ] 集成测试：`pov_mode` 缺失时工作流停下询问，不使用默认值
- [ ] 集成测试：(6) 确实暂停等待，未经确认不进入 (7)
- [ ] 产物检查：`report.md` 首页在 `coverage_gaps` 非空时含可信度声明
- [ ] 产物检查：`snapshot.json` 可被下次运行读取并算出 `new_since_last_inspection`
- [ ] **分页完整性**：对每个列表接口，取回条数 == `page.total_num`；不等时必须出现在 `coverage_gaps`
- [ ] **聚合降级**：人为屏蔽 `action=terms` 后，工作流仍能完成并自动切到备用源，且报告中出现口径声明
- [ ] 红线检查：全流程无任何写操作；报告全文 grep 不到明文口令
