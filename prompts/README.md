# Flocks 粘贴包 · TDP 巡检

八份可直接粘贴的 prompt，中英各四份。**按编号顺序装。**

```
prompts/
├── zh/  01-skill-methodology.md      Skill（两个 workflow 共用，先装）
│        02-workflow-daily-watch.md   日更轻量 workflow（定时无人值守）
│        03-workflow-deep-inspection.md  深度 workflow（人工触发，有人审硬停）
│        04-session-and-task.md       日常话术 + 定时任务 + session_id 推送
├── en/  同上四份
└── build.sh                          重新拼接 03（源 = workflow/tdp-inspection/workflow.md）
```

`zh/` 给国内或自用实例，`en/` 给国际客户场景或英文实例。**同一套内容，不要混装**。

## 装的顺序

1. **先装 Skill**（`01`）—— 两个 workflow 的 `compose` / `triage` 节点都要载入它，先装好再建 workflow。
   优先走「路径 A 拷文件」，别让 Rex 重新生成——那 4 个 references 是实测踩坑，Rex 编不出来。
2. **再建日更 workflow**（`02`）—— 这是新设计的，先跑通它。
3. **再建深度 workflow**（`03`）—— 已有需求契约，直接粘。
4. **最后配 session 话术和定时任务**（`04`）。

每个 workflow 粘完，Rex 先出 `workflow.md`，**在左侧「流程说明」人工复核并 Accept**，
再点顶部「生成工作流」出 `workflow.json`。官方明确说不要跳过这步，跳了就是让 Rex 自己跟自己对答案。

## 具体怎么装

Skill 和 Workflow 进 Flocks 的方式**完全不同**，别混：

| | Skill | Workflow |
|---|---|---|
| 动作 | **安装**（有现成文件） | **创建**（粘 prompt 让 Rex 生成） |
| 我给你的是 | 完整可用的 skill 目录 | 需求契约（`workflow.md`），**不是** `workflow.json` |
| 所以 | 拷进去就能用 | 必须让 Rex 生成一遍 |

### Skill —— 三条路，两条能用

**① `cp -r` 直接拷（Flocks 跑在本机时用这条）**

```bash
cp -r ~/work/TDP-Inspection-Flocks/skills/tdp-inspection-methodology ~/.flocks/plugins/skills/
```

**② 推 GitHub 私有库再装（Flocks 跑在别的机器上时用这条）**

```bash
flocks skills install github:<owner>/<repo> --skill tdp-inspection-methodology
```

也可以在 Skills 页面点 **Install Skill**，填 `github:owner/repo`。
GitHub 源能下完整目录，`references/` 不会丢。

**③ ❌ 本地路径安装 —— 别用**

```bash
flocks skills install /path/to/tdp-inspection-methodology   # 会丢 references/
```

官方文档明写：本地路径安装器**只读取并保存 `SKILL.md`，不复制 `references/` / `scripts/` /
`templates/`**。这个 skill 的判断依据全在 4 个 references 里（研判规则详解、工具字段速查、
数据口径陷阱、报告模板），那样装出来的是个空壳，Rex 载入后照样不知道分页会截断、
`terms` 会不可用。页面 Install Skill 填本地路径同理，是同一个 installer。

> 「本地路径」指 **Flocks 服务所在那台机器**的路径，不是你开浏览器这台。
> 装到用户级 `~/.flocks/plugins/skills/`，它的优先级高于项目级，同名会覆盖——别建重名。

**装完验证**（在 session 里）：

```text
/skills refresh
/skills
```

看到 `tdp-inspection-methodology` 才算成。看不到就查 `SKILL.md` 的 name/description 是否完整。
再确认一下 references 真的在：

```bash
ls ~/.flocks/plugins/skills/tdp-inspection-methodology/references/
```

应该有 4 个 .md。只有 SKILL.md 说明你走了路径 ③，重装。

### Workflow —— 只能让 Rex 生成

**我给你的是 `workflow.md`（需求契约），不是 `workflow.json`（机器定义）。**
Flocks 确实支持把 workflow 文件夹丢进 `~/.flocks/plugins/workflows/` 或导入 `workflow.json`，
但那需要一份已经生成并测试过的 json——我手上没有，也造不出来（它得由 Rex 在你的环境里
按实际可用的工具生成，硬写一份大概率对不上你的连接器）。

所以走这条：

1. Flocks → **Agent Studio → Workflow → 创建工作流**
2. 右侧 **Rex 工作台**，粘贴 `02`（或 `03`）**分隔线以内**的全部内容
3. Rex 生成 `workflow.md` → 左侧切到**「流程说明」**复核 → 点 **Accept**
4. 点顶部**「生成工作流」** → Rex 生成 `workflow.json`，并自动做格式校验、Python 语法校验、
   逐节点测试、集成测试
5. 切到**「流程图」**看节点、连线、schema、触发配置对不对

**第 3 步别跳。** 官方明确说先确认 `workflow.md` 再生成 `workflow.json`，
跳过等于让 Rex 自己跟自己对答案——它把需求理解歪了你也不知道，直接生成一堆调不通的节点。

**跑通之后建议导出 `workflow.json` 存一份**（Workflow 支持导入导出），
下次换环境或者手滑改坏了能直接导回来，不用重新生成。

**装完验证**：

```text
/workflows
```

两个都在就对了。

## 两档的分工

| | `tdp_daily_watch` | `tdp-inspection` |
|---|---|---|
| 触发 | Task Center 定时 | 人工 |
| 窗口 | 24h + 与昨日 diff | 用户指定（30/90 天） |
| 人审 | 无硬停 | 有硬停 |
| 回答 | 昨天有什么新变化 | 这套环境整体什么状况 |
| 输出 | 短简报推 IM | 完整英文报告 + 快照 |

日更的头号内容是**变化**，深度的头号产出是**处置优先级队列**（资产层 × 威胁层 join）。
两者共用同一个方法论 skill，所以定性口径一致。

---

## ⚠️ 装之前必须确认的（这些我确认不了）

### 1. 连接器版本 —— 最容易踩的坑

Flocks 里可能存在两代 TDP 连接器，**工具名完全不同**：

| 连接器 | 工具名形态 |
|---|---|
| `tdp_api_v3_3_10` | `tdp_system_status` / `tdp_log_search` … |
| `tdp_intl_api_v3_3_8` | `tdp_a1_*` / `tdp_a2_*` |

**所有 prompt 里写的都是第一种。** 如果你的设备接的是国际版连接器，工具名全对不上，
Rex 会生成一堆调不通的节点。

装之前在 session 里跑 `/tools`，或直接问 Rex：

```text
当前接入的 TDP 设备提供哪些工具？列出工具名。
```

对不上的话告诉我，我改 prompt 里的工具名。

### 2. 基线可能过期

已有交付包的基线是 **Flocks v2026.8.17 / TDP 连接器 3.3.10 / TDP API 文档 3.3.12**。
今天 2026-09-08，中间可能有版本变化。工具清单和字段名如果对不上，同样告诉我。

### 3. ThreatBook 情报工具在 Flocks 里的配额

日更版我做了限量设计（**只对保命清单条目富化**），但依据是你个人 key 的 100 次/天/接口。
`threatbook_io_*` 在 Flocks 里走的是哪个 key、配额多少，我不知道。
如果配额更紧，日更的富化范围还要再收。

### 4. 深度版不要配定时任务

它第 6 节点是人审硬停。定时跑会卡在那里等一个不存在的人。
只有日更版进 Task Center。

### 5. 日更 workflow 是新设计，没实测过

`tdp_daily_watch` 是这次新写的，只有深度版有实战基线（2026-06 某客户 POC）。
第一次跑重点看三件事：
- 分页有没有取全（对每个列表接口，取回条数 == `page.total_num`）
- `action=terms` 可不可用（不可用时有没有正确降级并声明口径）
- 首次运行是不是全标 `baseline` 而不是 `new`

---

## 我手上没有的东西

**TDP 的原始 API 接口文档我没有。** 知识库里搜到的 `API帮助文档` 全是联动防火墙的
（深信服 AF、网御 IPS、明御、PaloAlto、FortiGate），云 API 那份是 ATI 的。

不过这不影响这套 prompt —— Flocks 已经把 TDP API 封装成设备连接器工具了，
写 prompt 需要的是**工具名和字段**，而这些在 `skills/tdp-inspection-methodology/references/field-reference.md`
里有，且是实测沉淀的（分页默认 20 条不自动翻页、`size` 默认 10、`terms` 可能整个不可用、限流 50/s）。
这些比 API 规范值钱——规范不会告诉你哪个接口在真机上是坏的。

如果你能拿到 TDP API 原始文档，给我，我可以把工具清单和字段核一遍。

---

## 改动维护

- `03` 是从 `workflow/tdp-inspection/workflow.md` **自动拼接**的。改需求契约请改那份源文件，
  然后跑 `prompts/build.sh` 重新生成，**不要直接改 03**。
- `01` `02` `04` 是独立文件，直接改。
- 中英两版需要同步改——它们没有自动同步机制。
