# TDP 巡检 · Flocks 交付包

把 TDP 巡检能力搬到 Flocks 上。两档巡检 + 一个共用方法论 skill + 八份可直接粘贴的 prompt。

```
prompts/                                   ← 直接粘给 Flocks 的八份（中英各四）
  README.md                                  装的顺序 + 装之前必须确认的事项
  zh/ en/  01-skill-methodology.md           Skill（两个 workflow 共用，先装）
           02-workflow-daily-watch.md        日更轻量 workflow
           03-workflow-deep-inspection.md    深度 workflow（由 build.sh 自动拼接）
           04-session-and-task.md            日常话术 + 定时任务 + session_id 推送
  build.sh                                   重新拼接 03

workflow/tdp-inspection/workflow.md        深度巡检需求契约（03 的源文件，改这份）
skills/tdp-inspection-methodology/         研判方法论（拷进 Flocks 的源目录）
  SKILL.md + references/{triage-rules,field-reference,quirks,report-template}.md
```

## 两档分工

| | `tdp_daily_watch` | `tdp-inspection` |
|---|---|---|
| 触发 | Task Center 定时，无人值守 | 人工 |
| 窗口 | 24h + 与昨日 diff | 用户指定（30/90 天） |
| 人审 | **无硬停**（存疑进「待确认」区，不阻塞） | **有硬停**（等裁决才成文） |
| 回答 | 昨天有什么新变化 | 这套环境整体什么状况 |
| 输出 | 短简报推 IM + 快照 | 完整英文报告 + 快照 |
| 状态 | 新设计，**未实测** | 有实战基线（2026-06 某客户 POC） |

日更的头号内容是**变化**（「新增 3 台失陷」有用，「共 47 台有告警」没用）；
深度的头号产出是**处置优先级队列**（资产层 × 威胁层 join——设备自己的报告不做这个 join）。
两者共用同一个方法论 skill，定性口径因此一致。

## Workflow 和 Skill 怎么分

| | Workflow | Skill |
|---|---|---|
| 管什么 | **确定性计算**：采集 / 降噪 / 统计 / 交叉 | **判断**：定性 / 归因 / 定级 / 措辞 |
| 为什么 | 精确计数、去重聚合、两表 join 是 LLM 最不可靠的地方 | 定性判断、家族归因、叙事是 LLM 擅长的 |

依据 Flocks 官方判据：「下次还要按同一套步骤跑，做 Workflow；下次只是参考这次判断方法，做 Skill。」

## 开工

读 `prompts/README.md`——里面有装的顺序，以及**装之前必须确认的五件事**
（最重要的是连接器版本：`tdp_api_v3_3_10` 的工具名是 `tdp_*`，
`tdp_intl_api_v3_3_8` 是 `tdp_a1_*`/`tdp_a2_*`，两代完全对不上）。

## 基线

- Flocks `v2026.8.17`
- TDP 连接器 `tdp_api_v3_3_10`（22 个工具，20 读 + 2 写；写工具已明令禁用）
- TDP API 文档 `3.3.12`
- prompts 生成于 2026-09-08

> 基线可能已过期。工具名或字段对不上时，先跑 `/tools` 核对实际连接器版本。
