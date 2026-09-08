# TDP 工具调用手册（22 工具 · 连接器 tdp_api_v3_3_10）

开工前读完这份。**不要凭工具名猜参数。**

工具清单已对照 Flocks 设备页实际核实（连接器 `tdp_api_v3_3_10`，2026-09）：
**22 个 = 20 只读 + 2 写**。参数形态部分来自 TDP 3.3.8 API 定义，连接器是 3.3.10，
**标注「待验证」的项首次运行时用设备页的 `Test` 按钮确认一次**。

---

## 0. 通用约定

### 0.1 时间戳

- Unix **秒**（不是毫秒）
- `time_to` = 当前时刻，`time_from` = `time_to - 86400`
- **动态计算，绝不硬编码**
- 取数前先看 `tdp_system_status` 的时区状态——时区错则整个窗口错

### 0.2 参数包裹

多数列表类接口把过滤条件包在 `condition` 对象里：

```json
{ "condition": { "time_from": 1757260800, "time_to": 1757347200,
                 "page": 1, "page_size": 100, "assets_group": null } }
```

态势类（dashboard）接口多为平铺参数：`{"time_from": ..., "time_to": ..., "assets_group": ...}`。

### 0.3 分页（最容易造成事实性错误）

**默认每页 20 条，不会自动翻页。** 每次列表调用后：

1. 读 `page.total_num` / `page.total_pages`
2. 循环翻页取全
3. 取回条数 != `total_num` → 记 `partial` 进 `coverage_gaps`
4. **报告里的资产数字用 `total_num`**

实测：`service_list` 默认返回 20，而 `total_num = 445`。

### 0.4 限流

每端点 **50 req/s**，很宽松。并发 8–12 没问题，不用刻意串行。

---

## Phase 0 · 可信度（必须最先）

### `tdp_system_status`

默认返回全部子状态。覆盖：核心服务、硬件资源（CPU/内存/磁盘）、数据库（Elasticsearch）、
输入源、IOC 更新、云连通性、**时区**、各内部服务。

**必看的五项**：

| 子状态 | 看什么 | 不正常意味着 |
|---|---|---|
| 时区 | 是否与预期一致 | **窗口取错，所有数字作废** |
| IOC 更新 | 情报包是否最新、产品是否激活 | 检测面受限，"无告警"可能是漏报 |
| 云连通 | 到 ThreatBook 云的连通性 | IOC 富化失效，失陷判定只能靠本地特征 |
| 输入源 | 流量采集是否健康 | 可能整个网段没被看到 |
| 硬件 | 是否接近容量上限 | 可能丢包 |

> 三大引擎（TI / AI / Signature）**可能不同步，要分别看**，不能只看一个就下结论。
> License 临近到期必须进报告，否则没人推动。

**输出**：可信度评级（绿/黄/红）+ 降权声明草稿。**这一项决定报告第一页写什么。**

---

## Phase 1 · 态势总览

### `tdp_dashboard_status`

默认返回概览。已知可取的切面：概览、阻断信息、安全统计、攻击资产、文件检测、阶段统计。

**时间窗语义分裂——本 skill 最容易出错的地方：**

| 切面 | 时间窗 | 报告措辞 |
|---|---|---|
| 安全统计 / 阻断信息 / 威胁事件 / 风险 | **接受** `time_from`/`time_to` | "In the last 24 hours" |
| **攻击面（全部/对外暴露/新发现）** | **不接受**（当前全量快照） | "As of \<ts\>" |
| **攻击链阶段统计**（phaseSum） | **不接受** | "As of \<ts\>" |
| **恶意文件检测**（fileCheck） | **不接受** | "As of \<ts\>" |
| 登录入口风险 / Web 应用 / 服务分类 / 数据泄露 | **不接受** | "As of \<ts\>" |

> **已定**：攻击面一律按当前状态写，不去凑 24 小时口径（Martin 2026-09-08 拍板）。
> 即使连接器补了时间窗参数也不用——攻击面是存量概念，"24 小时内的攻击面"对客户没意义。

**绝不能写**「近 24 小时新增 N 个暴露资产」——除非你用的是"新发现"切面**且**已验证它认时间窗。
混用会让客户以为一天冒出这么多暴露面。

---

## Phase 2 · 威胁实况（窗口型，真正的 24 小时）

### `tdp_threat_monitor_list`

威胁事件列表（"威胁-实时监控"）。**查询范围硬性 ≤ 24 小时。**

> 这个限制在深度巡检里是缺陷（取不到跨周期数据），但在 24 小时巡检里**正好合适**——
> 它就是为这个窗口设计的。本 skill 应优先用它取当期威胁事件。

### `tdp_threat_alert_host`

两个 action：
- `alert_host_list` — 告警主机列表（每主机的威胁计数）
- `host_threat_list` — 单主机的威胁明细

**调用顺序**：先 `alert_host_list` 拿主机维度全景 → 对高危主机再 `host_threat_list` 深挖。
`alert_host_list` 也是 `terms` 不可用时的**主机级基线备用源**。

### `tdp_threat_intelligent_aggregation`

聚合攻击事件。相当于设备侧已做过一轮降噪，是 `terms` 的**一号备用源**。

**二级查询模式（重要）**：事件详情类要先拿到 incident id 再逐个查——
攻击成功标志、时间线、攻击者 IP、结果分布、被攻击实体、**攻击者 IP 信誉**都是按 incident 查的。

所以：**先取聚合事件列表 → 挑保命清单里的高价值事件 → 再逐个深挖**。
不要对所有事件做二级查询，会把时间耗光。

> **攻击者 IP 信誉是设备自带的**。先用它，能覆盖的就不必再调 ThreatBook 情报接口，省配额。

### `tdp_threat_external_attack`

外部（入站）攻击严重性分布。接受 `time_from` / `time_to`。

### `tdp_dashboard_status` → 威胁简报切面（分类的来源）

**专项威胁五类就在这里**，返回结构形如：
`webshell.*` / `mining.*` / `vul_0day.*` / `apt.*` / `cybercrime.count`

这是报告 3.1「Priority Threat Categories」的数据源。**五类都要取，没命中的写
`None observed`，不要静默省略**——"查了没有"和"没查"对客户是两回事。

> **待验证**：连接器里这个切面的参数名。设备页点 `Details` 看 `tdp_dashboard_status`
> 的完整描述，找威胁简报 / threat-topic 对应的取值。

### 分类相关字段速查

做报告 3.1 / 3.2 分类时会用到：

| 字段 | 来源接口 | 用途 |
|---|---|---|
| `threat.is_apt` | 告警汇总列表 | APT 标记，逐条级 |
| `direction` / `direction_desc` | 失陷主机汇总 / 事件搜索 | Compromised / Lateral / Inbound 三分 |
| `threat.phase` | 失陷主机汇总 / 事件搜索 | kill chain 阶段 |
| `phase_counts` | dashboard 攻击链切面 | 攻击链阶段分布（判覆盖盲区） |
| `is_target_attack` | 事件搜索 | 是否定向攻击 |
| `attack_type` / `attack_tool` | 事件搜索 | 攻击类型与工具 |
| `threat_tags` / `status_tags` | 失陷主机汇总 | 威胁标签 |
| `characters` | 主机威胁列表 | 含 `is_compromised` |

> **没有 ATT&CK 字段。** 整套接口不返回 tactic / technique。不要自己硬映。

### `tdp_mdr_alert_list`

MDR 研判结果。**客户未订阅时会失败——记 `coverage_gaps` 继续，不算故障。**

---

## Phase 3 · 统计基线

### `tdp_log_search`

两个 action：

**`action=search`** — 取证用，拿原始告警明细。

**`action=terms`** — 聚合统计，**相对基线的唯一精确来源**。

返回字段：`data.data[].key` / `.count` / `.global_percent` / `.first_occ_time` / `.last_occ_time`，
以及 `distinct` / `total` / **`global_total`**。

`global_total` 是**信噪比的分母**——它是设备侧全量基数，不受分页截断影响。
**绝不要用明细列表的条数当分母。**

**三个硬要求**：

1. **`size` 默认只有 10**，做 TOP 统计必须显式调大（200–1000）
2. **不支持 `page_size`**，别传
3. `terms` **可能整个不可用**（服务端能力缺失，非参数问题）→ 按 SKILL.md §3.3 降级并声明口径

**要算的基线**：

- 按 `threat.name` 聚合 → 噪声来源 TOP N（`global_percent`）
- 按源 IP 聚合 → 每源的 `distinct(dst)` 分布 → **取中位数**，供扫描器判定用
- 按 `threat.type` / `severity` 聚合 → 威胁构成

> 中位数是扫描器判据的分母。`terms` 不可用时改用 `alert_host_list` 算"每源关联目标主机数"，
> 两种口径都成立但**不可混用**，报告里要标明用的哪种。

---

## Phase 4 · 攻击面（快照型，注意措辞）

全部是**当前状态**，不是 24 小时增量。每个都要走**本文件 §0.3** 的分页自检。

| 工具 | 已知 action / 用途 |
|---|---|
| `tdp_machine_asset_list` | `service_list`（服务资产）/ `host_asset_list`（主机）/ `web_app_frameworks`（Web 应用框架） |
| `tdp_assets_domain_list` | 域名资产，支持按二级域名筛 |
| `tdp_login_api_list` | `summary` / `category` / `list` —— 登录入口 |
| `tdp_interface_list` | API 接口清单 |
| `tdp_interface_risk_list` | API 风险（注入、敏感信息等） |
| `tdp_asset_upload_api` | `summary` / `host_list` / `interface_list` —— 上传接口 |
| `tdp_cloud_facilities` | `access_source` 云服务访问源 / 实例信息 |

**三切面**（对每类资产都算）：对外暴露（Internet-facing）/ 新发现（设备标记）/ 带风险
（弱口令、脆弱性、敏感数据、高危端口、未识别服务）。

注意：
- **未识别服务是盲区，不是"没风险"**
- EOL 中间件是结构性风险，优先级高于普通漏洞
- 资产数字必须标时间语义——NDR 看到的资产是"在网络上说过话的资产"

---

## Phase 5 · 风险隐患

| 工具 | 注意 |
|---|---|
| `tdp_vulnerability_list` | `condition` 支持 severity / vulnerability_type / 分页 |
| `tdp_login_weakpwd_list` | **强制 `is_plaintext = false`**（红线，见 SKILL.md 第 6 节红线第 2 条） |
| `tdp_privacy_diagram` | 明文敏感信息拓扑，接受时间窗 |

**弱口令要看登录结果**：检出弱口令**且有成功登录 = 已被利用**，不只是隐患。
这条直接进 P0 交叉队列。

---

## Phase 6 · 取证（仅高价值事件，按需）

| 工具 | 用法 |
|---|---|
| `tdp_pcap_download` | 按 `alert_id` + `occ_time` 取报文。**只对保命清单里的事件调** |
| `tdp_file_download` | 按哈希取恶意文件。**只对命中样本调** |

这两个返回二进制，别对批量事件调用。

---

## ⛔ 禁用工具（绝不调用）

| 工具 | 为什么禁 |
|---|---|
| `tdp_platform_config` | 管理平台配置，覆盖资产配置等——**会改变被巡检对象** |
| `tdp_policy_settings` | 管理策略配置，覆盖自定义情报、黑名单、联动阻断、告警处置状态 |

**巡检工具不改变被巡检对象。** 而且写操作会污染下次巡检的对比基线。
即使用户中途说"顺手把这个 IP 封了"，也要拒绝——那是响应动作，不是巡检职责，
应该由客户在自己的流程里做。

---

## 待验证清单（首次运行时确认，结果回填本文件）

- [ ] **`tdp_threat_monitor_list` 的确切参数、返回结构，以及与 `tdp_threat_alert_host` 的数据是否重复**
      —— 它是 Phase 2 的入口，最该先单独 Test 一次
- [ ] `tdp_dashboard_status` 支持哪些切面参数名，**尤其是威胁简报切面**
      （apt / vul_0day / cybercrime / webshell / mining 五类从那里取）—— 设备页 `Details` 可看完整描述
- [ ] `tdp_log_search action=terms` 在本设备上是否可用
- [ ] `tdp_mdr_alert_list` 本设备是否订阅
- [ ] 各列表接口的 `page_size` 上限
