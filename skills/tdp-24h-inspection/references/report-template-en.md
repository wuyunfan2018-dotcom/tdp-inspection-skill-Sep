# 英文客户报告 · 骨架与措辞

正文全英文，术语对齐 TDP 产品英文 UI。骨架下面的中文是**写法指引，不进报告**。

---

## 骨架

```markdown
# TDP Security Inspection Report
**Device**: <device name>   **Prepared**: <YYYY-MM-DD HH:MM TZ>

## 1. Executive Summary

<One-sentence conclusion.>

**Observation windows**
- Threat activity: last 24 hours (<from> — <to>, <TZ>)
- Attack surface & asset inventory: point-in-time snapshot as of <ts>

**Confidence statement**            <- coverage_gaps 非空时必须有，否则删掉整块
This inspection did not cover <X, Y, Z> because <reason>. Conclusions regarding
<affected areas> should be treated as provisional.

## 2. Remediation Priority Queue

| # | Priority | Asset | Asset-side evidence | Threat-side evidence | Recommended action |
|---|---|---|---|---|---|

## 3. Threat Findings

### 3.1 Priority Threat Categories           <- 横切索引，设备原生五类
        APT · 0-day Exploitation · Cybercrime · Webshell · Mining
### 3.2 Findings by Attack Direction         <- 详情主体，TDP 原生方向三分
        3.2.1 Compromised  /  3.2.2 Lateral Movement  /  3.2.3 Inbound Attack
### 3.3 Detection Capability Validation      <- 仅 pov_mode A；模式 B 整节删除
### 3.4 Excluded — Statistical Artifacts

## 4. Attack Surface (as of <ts>)

Overview + three facets: Internet-facing / Newly Discovered / Carrying Risk

## 5. Risk Inventory

Vulnerabilities · Weak Passwords · Sensitive Data Exposure

## 6. Detection Efficacy & Tuning

Signal-to-noise · Top noise sources · Suspected false positives · Coverage gaps

## 7. Security Recommendations                <- 设备自带报告留白的一章，本报告的主要增量

## 8. Items for Confirmation

Appendix: Data basis notes · IOC list · Folded bucket statistics
```

---

## 每节写法

### 1. Executive Summary

一句话结论要**可执行**，不要"整体安全态势良好"这种。
坏例：`Overall security posture is stable.`
好例：`Two hosts show confirmed C&C communication and require immediate isolation;
the remaining 47 alerts are attributable to scheduled internal scanning.`

**两个时间窗都要印**，且分别标注语义（见 tool-playbook §Phase 1）。
可信度声明只在 `coverage_gaps` 非空时出现——没有缺口就不要写一段"本次很完整"的废话。

### 2. Remediation Priority Queue

**这是整份报告最核心的一节**，放在威胁发现之前——客户先要知道做什么，再看细节。

每条必须带**两维依据**：资产侧（暴露状态/服务/端口/弱口令）+ 威胁侧（威胁名/结果/计数/时间）。
**只有一维的不进队列**，放到第 5 或第 8 节去。

P0 = 已被利用或即将被利用；P1 = 结构性缺陷；P2 = 隐患未被利用。

### 3. Threat Findings

**分类依据（三个正交维度，分层使用，不要混成一级目录）**

| 维度 | 取自哪里 | 在报告里的位置 |
|---|---|---|
| **专项威胁类型** | 设备原生五类：`apt` / `vul_0day` / `cybercrime` / `webshell` / `mining`（威胁简报切面）+ `threat.is_apt` | **3.1 横切索引** |
| **攻击方向** | `direction` / `direction_desc` → Compromised / Lateral Movement / Inbound Attack | **3.2 详情主体** |
| **可信性定性** | 三分法结论（`real_threat` / `capability_validation` / `customer_own_behavior` / `tdp_artifact` / `pending_review`） | **每条发现的属性标注**，不做分节 |

外加 **kill chain 阶段**（`threat.phase`，配合 `attack_chain` 的 `phase_counts`）作为每条的位置标注。

> **不做 ATT&CK 映射。** TDP 3.3.8 的接口不返回 tactic / technique 字段，自己硬映会引入
> 错误归类。客户若明确要求 ATT&CK，单独提出来人工做，不要让 skill 自动生成。

#### 3.1 Priority Threat Categories

**这一节的存在理由：这五类天然量少，按方向分类会被淹没在长尾里，而它们恰恰是客户最先问的。**

每类给：命中条数 / 涉及主机 / 最高严重度 / **指向 3.2 具体条目的指针**。
**这是索引不是详情**——同一条发现不要在 3.1 和 3.2 各写一遍完整内容。

没有命中的类别**也要列出并写 `None observed in this window`**。
静默省略会让客户以为没查——"查了没有"和"没查"是两回事。

其中 `vul_0day` 和 `apt` 命中时，**必须同时进第 1 节执行摘要和第 2 节优先队列**，不能只待在这里。

#### 3.2 Findings by Attack Direction

按 **Compromised → Lateral Movement → Inbound Attack** 排序，这个顺序即处置紧迫度：
已失陷的比正在横移的急，正在横移的比还在门外打的急。

每条发现带：定性标注 / kill chain 阶段 / 严重度 / 命中的专项类型（若有）/ 证据指针。

#### 3.3 Detection Capability Validation

**模式 A 的生命线。** 我方模拟攻击/投放的样本**必须单独成节**，
说明这些是受控测试流量、用于验证检出能力，不是环境中的真实威胁。

把我方打的攻击混进 3.2 拿给客户看，是本 skill 能犯的最严重错误。
**模式 B 下整节删除**，不要留一个空节。

#### 3.4 Excluded — Statistical Artifacts

要说明**为何排除**，不能只列一句"误报"。给机制解释（NAT 回环、反代改写方向、
同会话多规则命中等）。

### 4. Attack Surface

标题里的 `as of <ts>` 不许省。三切面分别给数字，每个数字来自 `total_num`。
未识别服务单独列——它是盲区，不是"没风险"。

### 6. Detection Efficacy & Tuning

信噪比的分母用 `global_total`。降级取数时**必须写明口径**：
`Based on host-level aggregation; the ratio is an estimate rather than an exact proportion.`

疑似误报要给**可执行的调优动作**（add an ignore rule / reclassify / add X-Forwarded-For /
register the reverse-proxy asset），不能只说 "this is a false positive"。

### 7. Security Recommendations

**这一章是本报告相对 TDP 自带导出报告的主要增量**（设备那份是空的）。
按优先级排序，每条对应第 2 节队列里的条目，写成客户能直接派工的动作，
不要写成"建议加强安全管理"这类没有承接对象的话。

### 8. Items for Confirmation

只放**客户才能认领**的事项：疑似客户自有扫描器/BAS/红队、运维隧道、员工远控软件、
定性存疑项。每条给证据 + 我方倾向 + **两种判法各自的后果**，让客户能判。

---

## 措辞原则

1. **不夸大。** 没有"严重威胁"就不要造。真实的两台失陷比虚构的二十条高危有说服力。
2. **不替客户拍板。** 生产环境流量的性质存疑就写存疑，列证据交客户。
3. **不写未经授权的来源对比。** 不要写 "not found in public sources" 这类——
   我们只用 ThreatBook 情报立论。
4. **数字必须可追溯。** 每个数字能指回工具、调用、时间窗。
5. **区分"未发现"和"未覆盖"。** `coverage_gaps` 里的东西是后者，
   不能写成 "no threats found in this area"。
6. **不写明文口令。** 只写用户名、口令长度与强度特征、命中规则。

---

## 术语表（对齐 TDP 产品英文 UI，不自创译法）

| 中文 | 英文 |
|---|---|
| 外部攻击 / 入站攻击 | Inbound Attack |
| 横向移动 | Lateral Movement |
| 失陷 | Compromised |
| 告警 | alert |
| 威胁事件 | incident |
| 旁路阻断 | TCP reset |
| 攻击面 | Attack Surface |
| 弱口令 | Weak Passwords |
| 处置状态 | Resolution Status |
| 脆弱性 | Vulnerability |
| 资产组 | Asset Group |

需要更多术语时查 `tdp-manual-translator` skill（如果环境里有），**不要临时造词**。
