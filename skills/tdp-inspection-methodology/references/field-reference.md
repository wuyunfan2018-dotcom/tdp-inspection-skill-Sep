# TDP 工具与字段速查

基线：Flocks 连接器 `tdp_api_v3_3_10`，TDP API 文档 3.3.12。
**遇到工具名对不上，先查设备用的是哪代连接器**——Flocks 里可能同时存在
`tdp_intl_api_v3_3_8`（细粒度，一端点一工具，`tdp_a1_*` / `tdp_a2_*`）和
`tdp_api_v3_3_10`（粗粒度，22 个工具靠 `action` 切子接口）。两代工具名完全不同。

---

## 1. 只读工具清单（20 个）

| 工具 | 关键 action / 用途 |
|---|---|
| `tdp_system_status` | 默认返回全部状态汇总；可切核心/DB/硬件/服务/输入/IOC更新/云连通/时区 |
| `tdp_dashboard_status` | 概览 / 阻断 / 安全统计 / 攻击资产 / 文件检测 / 阶段统计 |
| `tdp_threat_alert_host` | `alert_host_list` 告警主机列表；`host_threat_list` 单主机威胁列表（需先拿到资产标识） |
| `tdp_threat_intelligent_aggregation` | 聚合攻击事件；可查攻击成功统计 / 时间线 / 攻击者 |
| `tdp_threat_external_attack` | 外部攻击严重性分布 |
| `tdp_log_search` | `search` 日志搜索 / `terms` 字段聚合。**`terms` 在部分部署上服务端未加载（Spring bean 缺失），换参数无用，必须有降级路径** |
| `tdp_machine_asset_list` | `service_list` / `host_asset_list` / `web_app_frameworks` |
| `tdp_assets_domain_list` | 域名资产 |
| `tdp_login_api_list` | `summary` / `category` / `list` |
| `tdp_login_weakpwd_list` | 弱口令列表 |
| `tdp_interface_list` | API 接口清单 |
| `tdp_interface_risk_list` | API 风险清单。**实测部分部署上返回后端通用错误，与参数无关**，取不到就记 coverage_gap |
| `tdp_asset_upload_api` | `summary` / `host_list` / `interface_list` |
| `tdp_cloud_facilities` | `access_source` / `assets_info` / `instance_list` / `instance_detail` |
| `tdp_privacy_diagram` | 明文敏感信息拓扑 |
| `tdp_vulnerability_list` | 脆弱性列表 |
| `tdp_pcap_download` | 按 `alert_id` + `occ_time` 下载报文 |
| `tdp_file_download` | 按样本哈希下载 |
| `tdp_mdr_alert_list` | `indicator` / `list`（客户订阅 MDR 才有数据） |

**禁用（写工具）**：`tdp_policy_settings`（自定义情报 / IP信誉 / 旁路阻断 / 联动阻断 / **改告警处置状态**）、
`tdp_platform_config`（资产增删改 / 白名单 / 级联 / 自定义规则）。

**不用**：`tdp_threat_monitor_list` —— 查询时间范围硬性 ≤24 小时，巡检需要跨周期数据。

---

## 2. 告警主机筛选器

`tdp_threat_alert_host` → `alert_host_list`（底层 `/api/v1/host/getFallHostSumList`）

| 参数 | 取值 | 巡检用途 |
|---|---|---|
| `time_from` / `time_to` | Unix 秒，**必填** | 时间窗 |
| `threat_characters` | `["is_compromised"]` | **第 2 层失陷主机直接筛出** |
| `direction` | `in` 入站 / `out` 失陷 / `lateral` 横移 | 攻击链阶段切分 |
| `threat_type` | `recon` `exploit` `virus` `tunneling` `infil` `dc` `shell` `trojan` `rat` `unknown_url` `file` `phishing` `post_exploit` | 保命清单靠它筛 |
| `severity` | `0` info `1` low `2` medium `3` high `4` critical | 分层下钻 |
| `disposal_status` | `1` 未处置 `2` 处置中 `3` 已处置 | **第 5 层运营成熟度** |
| `asset_section` | `server` / `terminal` | 资产类型 |
| `assets_group` | 业务组 ID 数组 | 范围限定 |
| `page` | `{cur_page, page_size, sort_by, sort_flag}`，支持 `sort_by: severity` + `sort_flag: desc` | 分层下钻取 TOP N |

---

## 3. 日志字段（研判主要靠这些）

`tdp_log_search` → `action=search`（底层 `/api/v1/log/searchBySql`）

| 字段 | 含义 | 研判价值 |
|---|---|---|
| `threat.is_connected` | 是否建连，`1` = 是 | **最硬的失陷信号**，优先级高于 result=success |
| `threat.characters` | 威胁特征，如 `["is_compromised"]` | 失陷标记 |
| `threat.result` | `success` / `failed` / `unknown` | 攻击结果。**unknown ≠ 失败** |
| `threat.is_apt` | `1` = 命中黑客组织 | APT 归因，进保命清单 |
| `threat.type` | 威胁类型，如 `c2` | 保命清单判据 |
| `threat.name` | 威胁名 | 聚合主键 |
| `threat.phase` | 攻击阶段，如 `post_exploit` | 攻击链位置 |
| `threat.level` | `attack` / `action` / `risk` | 日志大类 |
| `threat.ioc` | 关联 IOC | 富化输入 |
| **`net.real_src_ip`** | **真实源 IP** | **与 `net.src_ip` 不一致 = 存在反向代理/NAT，入站被误记为横移** |
| `net.src_ip` / `net.dest_ip` | 观测到的源/目的 | 会话去重主键 |
| `net.src_port` / `net.dest_port` | 端口 | 会话去重主键 |
| `net.type` | 应用层协议 | 协议维度 |
| `src_tag` / `dest_tag` | `Internal` / `External` | 方向判定（**客户用公网段做内网时会误标，须与资产表比对覆盖**）|
| `direction` | 告警方向 | 攻击链阶段 |
| `machine` | 告警主机 | 主机维度 |
| `data` | 域名/IP/URL 主体 | 证据 |
| `id` | 告警 ID | 去重 + PCAP 下载 |
| `time` | 告警时间 | 时序分析 |

`net_data_type`：`attack` 攻击 / `risk` 风险 / `action` 敏感行为 / `info` 网络 / `flow` 流量

---

## 4. 聚合接口（信噪比与相对基线全靠它）

`tdp_log_search` → `action=terms`（底层 `/api/v1/log/terms`）

**入参**

| 参数 | 说明 |
|---|---|
| `term` | 聚合字段，如 `threat.name` / `net.src_ip` / `net.dest_ip` / `net.http.url` |
| `sql` | 过滤表达式（**不是完整 SQL，禁止 `SELECT * FROM`**），如 `threat.level = 'attack'` |
| `size` | 桶数量。**工具默认只有 10，做统计必须显式调大**（建议 200–1000） |
| `net_data_type` | 日志类型数组 |

**返回**

| 字段 | 用途 |
|---|---|
| `data.data[].key` / `.count` | 桶键与计数 |
| **`data.data[].global_percent`** | **该值占全部记录的百分比 → 帕累托切分直接用它** |
| `data.data[].first_occ_time` / `.last_occ_time` | 时间跨度 |
| `data.distinct` | 唯一值数量 → **扫描器判据（单源 distinct 目标数）** |
| **`data.global_total`** | **全量基数 → 信噪比分母，不受分页影响** |

> **重要**：工具**不支持 `page_size`**，只有 `size`。统计优先走本接口，
> 不要用明细列表累加（会被分页截断）。
>
> ⚠️ **本接口可能整个不可用**：实测部分 TDP 部署返回
> `No qualifying bean of type '...LogTermService'`，与时间窗/聚合字段/日志类型无关。
> 降级顺序：`tdp_threat_intelligent_aggregation`（设备自带事件聚合）→
> `tdp_threat_alert_host action=alert_host_list`（主机级）→ `action=search` + 客户端聚合。
> 降级后信噪比分母为估算值，报告须声明口径。

---

## 5. 弱口令接口

`tdp_login_weakpwd_list`（底层 `/api/v1/login/weakpwd/list`）

| 参数 | 说明 |
|---|---|
| `result` | `success` / `failed` / `unknown` → **`success` 即已被利用，不只是隐患** |
| `app_class` | 登录入口类型 |
| **`is_plaintext`** | **强制 `false`。开启会返回明文口令，报告绝不落明文** |
| `page.page_size` | 可到 2000 |

**返回**：`username` / `data`（登录接口）/ `rule_items`（命中规则与描述）/ `login_time` /
`src_ip` / `result` / `category`（`web` / `remote_login` / `file_share` / `db` / `email`）

---

## 6. 态势接口

`tdp_dashboard_status` 的安全统计（底层 `/api/v1/dashboard/security`）

| 字段 | 取值 |
|---|---|
| `level` | `SUSPICIOUS` / `LOW` / `MEDIUM` / `HIGH` / `CRITICAL` |
| `compromised_host_count` | 待处置失陷主机数 |
| `unhandled_host_count` | 待处置主机总数 |

> 与逐项发现做**自洽性检查**：等级偏低但存在确认失陷时，报告中指出矛盾并建议复核阈值。

---

## 7. 分页

列表类接口**默认每页 20 条，不会自动翻页**。响应中的 `page` 对象带：

| 字段 | 说明 |
|---|---|
| `page.total_num` | **总记录数 —— 报告里该用的数字** |
| `page.total_pages` | 总页数 |
| `page.page_size` | 每页条数 |
| `page.cur_page` | 当前页 |

实测 `service_list` 默认返回 20 条而 `total_num=445`。**必须循环翻页取全**，
并自检 `取回条数 == total_num`，不等则标 `partial`。

---

## 8. 通用约束

- 所有接口限流 **50/s**，采集并发 8–12 完全安全。
- 时间戳一律 **Unix 秒**，必须动态计算，不得硬编码。
- 鉴权由 Flocks 设备连接器处理，Agent 不碰签名。
