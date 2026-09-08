#!/bin/bash
# 重新拼接深度巡检 prompt（中文版）
# 源 = workflow/tdp-inspection/workflow.md，改需求契约请改那份，然后跑本脚本
set -e
cd "$(dirname "$0")/.."
OUT=prompts/zh/03-workflow-deep-inspection.md
{
cat <<'HEAD_EOF'
# 粘贴位置：Flocks → Agent Studio → Workflow → 创建工作流 → 右侧 Rex 工作台

> 这是**深度巡检**（人工触发，有人审硬停），与日更 `tdp_daily_watch` 分工见 02。
> 粘贴下面**分隔线以内**的全部内容。Rex 生成 `workflow.md` 后，左侧「流程说明」复核并 Accept，
> 再点顶部「生成工作流」出 `workflow.json`。**不要跳过人工复核。**
>
> 正文由 `workflow/tdp-inspection/workflow.md` 自动拼接生成，改动请改那份源文件后重跑
> `prompts/build.sh`，不要直接改本文件。

---

帮我创建一个工作流：`tdp-inspection`。下面是完整的需求契约，请据此生成 `workflow.md` 与 `workflow.json`。

生成要求：
- 每个节点都要有明确的输入/输出 schema
- 生成后先逐节点测试，再跑集成测试
- 测试数据和产物落 Workspace outputs 目录
- 第 6 节点 `human_review` 是**硬停**，必须真的暂停等待用户输入，不得自动跳过

---

HEAD_EOF
cat workflow/tdp-inspection/workflow.md
} > "$OUT"
echo "rebuilt $OUT ($(wc -l < "$OUT") lines)"
