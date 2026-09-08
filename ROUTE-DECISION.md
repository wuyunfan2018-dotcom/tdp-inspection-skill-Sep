# 路线选型 · TDP 巡检怎么接 Flocks

2026-09-08。给 Martin 决策用。

## 结论先说：两条路线其实已经汇合了

我原以为要在「自建 98 个 API tools」和「用 Flocks 内置连接器」之间二选一。**不用选——
Flocks 已经把那 98 个 API 做成连接器了。**

证据链：

| 事实 | 来源 |
|---|---|
| `TDP-API-Tool-Schemas.json` 的命名规范是 `tdp_<group>_<verb>_<entity>` | schema 文件 `tool_naming_convention` |
| 实际工具名形如 `tdp_a1_core_status` / `tdp_a2_dashboard_get_status` / `tdp_a3_machine_list_services` | schema 的 98 条 `apis` |
| 该 schema 标注 `product: ThreatBook TDP (NDR) 3.3.8` | schema `product` 字段 |
| Flocks 里存在连接器 `tdp_intl_api_v3_3_8`，工具名形态 `tdp_a1_*` / `tdp_a2_*` | 交付包 README 的既有记录 |

命名规范吻合、能力组编号吻合、版本号吻合。**`tdp_intl_api_v3_3_8` 就是这份 98 API schema 的
Flocks 托管版**。所以自建 tools 那条路（自己实现 HmacSHA256 签名、自己维护 98 个 tool 定义、
自己存 api_key/secret）没有必要走——凭据交给 Flocks 设备层管，能力一个不少。

> 这一条需要你在 Flocks 里跑 `/tools` 确认一次。我是从命名和版本推断的，没有活实例可验。

## 真正的选型：用哪个连接器

| | `tdp_api_v3_3_10` | `tdp_intl_api_v3_3_8` |
|---|---|---|
| 工具数 | 22（20 读 + 2 写） | ~98（71 读 + 27 写） |
| 粒度 | **粗**：一个工具多 action（如 `tdp_machine_asset_list` 带 `service_list`/`host_asset_list`/`web_app_frameworks`） | **细**：一 API 一工具 |
| 版本 | 3.3.10（新） | 3.3.8（旧） |
| 今天的 prompt | **按这套写的** | 工具名全对不上 |
| 实测踩坑 | 有（分页截断、`terms` 不可用、`size` 默认 10） | 无 |

### 粗粒度的代价：能力可能被封装掉

连接器把多个 API 合成一个工具时，未必把所有 action 都暴露出来。对照 98 API 清单，
**以下能力今天的 prompt 里没有，而 TDP 原生是有的**——它们恰好都对得上我设计的巡检维度：

| 原生 API | 能干什么 | 对应今天设计里的哪块 |
|---|---|---|
| `tdp_a2_dashboard_alert_level_trend` | 告警等级趋势 | 日更的 diff **设备原生就有**，不必全靠快照自己算 |
| `tdp_a2_dashboard_attack_surface_new` | 新增攻击面 | 资产三切面的「新发现」 |
| `tdp_a2_dashboard_top_unsolved_hosts` | 未处置主机 TOP | 第 5 层运营成熟度（未处置比例） |
| `tdp_a2_dashboard_attack_chain` (`phaseSum`) | 攻击链阶段统计 | 第 4 层「覆盖盲区：各阶段是否都有数据」 |
| `tdp_a5_incident_attacker_ip_reputation` | **攻击者 IP 信誉（设备自带）** | 可能省掉一部分 ThreatBook API 调用，缓解日更配额压力 |
| `tdp_a5_host_get_fall_host_sum_list` | 失陷主机汇总 | 保命清单的主入口 |
| `tdp_a5_incident_timeline` | 事件时间线 | 失陷主机的次生行为追查 |
| `tdp_a6_log_search_by_sql` | **SQL 方式搜日志** | 比 `tdp_log_search` 表达力强，聚合降级时可能是更好的备用源 |
| `tdp_a8_cascade_children` | 级联子平台清单 | 多级部署客户（总部 + 分厂各一套，分厂镜像单独接入） |

其中前三个尤其值得注意：**我今天让 workflow 自己算的 trend / new / unsolved，设备原生都有接口。**
自己算不是错（快照 diff 的语义更严格，且不依赖设备口径），但能直接取就没必要全自己算，
而且两边可以互相校验。

### 细粒度的代价：98 个工具会撑爆 Rex 的选择空间

LLM 在近百个工具里自由选择，选错率明显上升。但**这个问题只在 session 里让 Rex 自由发挥时存在**——
在 workflow 里节点是固定调用的，不靠 LLM 选，98 个工具不构成问题。

所以：**workflow 用细粒度连接器，session 里日常问答用粗粒度的**，两个都装也行，
它们工具名不冲突。

## 建议

1. **先在 Flocks 跑一次 `/tools`**，确认两个连接器实际存在哪个、各自暴露了哪些工具名。
   这是所有后续决策的前提，我推断不了。
2. 如果 `tdp_intl_api_v3_3_8` 在 → **workflow 走它**，我把今天两份 prompt 的工具名从
   `tdp_*` 换成 `tdp_a*_*`，并把上面那 9 个漏掉的能力加进采集节点。
3. 如果只有 `tdp_api_v3_3_10` → 今天的 prompt 直接可用，但要接受上面那些能力取不到；
   或者用 `/tools info <name>` 逐个查它的 action 列表，看能不能挖出来。
4. 版本差是个真问题：连接器 3.3.8 vs 3.3.10。**如果客户 TDP 是更新的版本，3.3.8 连接器可能缺新接口**。
   实际用哪个以设备实测为准。

## 我没有验证的

- 两个连接器在你的 Flocks 里到底装了哪个（或都装了）
- `tdp_api_v3_3_10` 的 22 个工具各自支持哪些 action——粗粒度封装可能已经覆盖了上面「漏掉」的能力，
  只是我从工具名看不出来
- 98 API schema 标的是 TDP 3.3.8，你现在客户现场的 TDP 是什么版本
- 那 9 个「原生有」的接口，在实际设备上是否都可用（部分可能依赖订阅模块）
