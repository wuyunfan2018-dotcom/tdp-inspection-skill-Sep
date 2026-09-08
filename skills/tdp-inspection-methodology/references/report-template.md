# 报告骨架与措辞原则

报告正文 **英文**。结构按**行动优先**排列，不按分析顺序——
读者要的是「我该干什么」，不是「你怎么分析的」。

---

## 骨架

```
1. Executive Summary
   - One-line verdict
   - [Data Confidence Statement]   <- coverage_gaps 非空时必须出现
   - Observation windows (asset window / threat window，两个都印)

2. Remediation Priority Queue      <- 最核心，放最前
   P0 / P1 / P2
   每条：Host + Asset-side evidence + Threat-side evidence + Recommended action

3. Threat Findings
   按定性分组：
   - Confirmed threats
   - Customer-owned activity (pending customer confirmation)
   - Statistical artifacts (excluded, with reason)
   - Pending review

4. Assets & Attack Surface
   Overview + 三切面：Internet-facing / Newly discovered / Carrying risk

5. Detection Efficacy & Tuning
   Signal-to-noise / Top noise sources / Suspected false positives /
   Coverage gaps / Tuning actions

6. Operational Maturity
   Resolution status distribution / Asset inventory completeness / Response policy usage

7. Items for Customer Confirmation
   只有客户能认领的事项，逐条列证据与我方倾向

Appendix
   Folded buckets statistics / IOC list / Data caveats
```

---

## 每一节的写法要点

### 1. Executive Summary

- 一句话结论要给**方向**，不是罗列数字。
- **可信度声明**：`coverage_gaps` 非空时必须写明「以下结论需降权：因 X / Y 未采集到，
  『未发现威胁』应理解为『在当前可见范围内未发现』」。
- 两个时间窗都要印，且标明哪个数字属于哪个窗。

### 2. Remediation Priority Queue

- 每条**必须有两维依据**。只有一维的不进队列。
- 建议动作要**可执行**，写清责任方向（网络组 / 系统组 / 应用组 / 安全组）。
- 排序按 P0 > P1 > P2，**不按告警数量**——量大不等于危险。

### 3. Threat Findings

- 先写确认威胁，再写客户自有行为，最后写排除项。
- **排除项也要写**，并说明为什么排除——这体现研判做过，不是漏掉了。
- 折叠桶给统计与代表样本，注明可展开。

### 4. Assets & Attack Surface

- 三切面分开呈现，不要混成一张大表。
- 「新发现」两个口径分开印，注明含义差异。
- EOL 组件、未识别服务单独拎出来。

### 5. Detection Efficacy & Tuning

- 信噪比要写清分母来源（聚合接口全量基数）。
- 每个疑似误报都要配**可执行的调优动作**，不能只说「这是误报」。
- 覆盖盲区要区分「真的没有」和「没采到」。

### 6. Operational Maturity

- 写给管理层，不要写成技术动作。
- 未处置比例、资产台账完整度是两个最有说服力的指标。

### 7. Items for Customer Confirmation

- 每条写清：**为什么重要**（两种答案会导致完全不同的处置）+ 我方倾向 + 依据。
- 这一节同时起免责作用：不代客户对生产环境拍板。

---

## 措辞原则

| 场景 | 写法 |
|---|---|
| 有我方模拟攻击（模式 A） | 我方流量 -> "detection capability validation"；客户流量 -> "real-network finding"。**分开写** |
| 纯真实流量（模式 B） | 统一 "detected in the customer's live environment" —— 真网实测非摆拍，是更强的表述 |
| 定性存疑 | "pending customer confirmation"，附证据与倾向 |
| 未富化的 IOC | "not enriched — cloud intelligence unavailable"，**不编造结论** |
| 弱口令 | 只写用户名、口令长度与强度特征、命中规则。**绝不写口令内容** |

**通用**：不夸大、不替客户对真实环境拍板根因、不写未经授权的来源对比
（如「公开源查不到」——我们没有授权使用第三方源，也就无从比较）。

---

## 术语（对齐产品英文 UI，不自创）

Inbound Attack · Lateral Movement · Compromised · alert · incident · TCP reset ·
Attack Surface · Weak Passwords · Resolution Status · Unresolved · Incident Hosts ·
Internet-facing · Newly Discovered
