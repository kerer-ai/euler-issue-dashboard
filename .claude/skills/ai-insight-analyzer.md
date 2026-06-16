---
name: ai-insight-analyzer
description: 采集 GitCode issue 数据并用 AI 进行主题聚类和优先级分析，生成 ai-insights.json 供 Dashboard 使用
triggers: 生成AI分析、运行洞察分析、更新AI洞察、分析issue趋势、刷新分析数据、/ai-insight-analyzer
---

# AI Insight Analyzer

采集 gitcode-dev/euler-api-list 仓库的全部 open issue，预处理数据后由 Claude 执行 AI 分析（主题聚类 + 优先级判断 + issue 关联），输出 `ai-insights.json`。

## 执行流程

### Step 1: 数据采集

执行以下命令拉取全部 open issues：

```bash
cd /home/wangsike/workspace/tmp/gitcode-dev

python3 << 'PYEOF'
import subprocess, json

all_issues = []
page = 1
while True:
    result = subprocess.run(
        ['gc', 'issue', 'list', '-R', 'gitcode-dev/euler-api-list',
         '--state', 'open', '--limit', '100', '--page', str(page), '--json'],
        capture_output=True, text=True, timeout=30
    )
    batch = json.loads(result.stdout)
    if not batch: break
    all_issues.extend(batch)
    print(f"Page {page}: {len(batch)} issues (累计 {len(all_issues)})")
    if len(batch) < 100: break
    page += 1

community_labels = ['Ascend', 'CANN', 'openEuler', 'OpenHarmony', 'MindSpore', 'HiSpark', 'openGauss', 'openlibing', 'Cangjie']
status_labels = ['待验收', '待排期', '高优先级', '已拒绝', '长期演进']

processed = []
for issue in all_issues:
    labels = [l['name'] for l in (issue.get('labels') or [])]
    itype = 'bug' if 'bug' in labels else ('enhancement' if 'enhancement' in labels else ('question' if 'question' in labels else 'other'))
    communities = [c for c in community_labels if c in labels] or ['其他']
    tags = [s for s in status_labels if s in labels]
    user = issue.get('user') or {}
    reporter = user.get('name', '') or user.get('login', '') or 'unknown'
    processed.append({
        'number': issue['number'],
        'title': issue['title'],
        'html_url': issue['html_url'],
        'reporter': reporter,
        'reporter_login': user.get('login', '') or 'unknown',
        'type': itype,
        'communities': communities,
        'status_tags': tags,
        'labels': labels,
        'created_at': issue.get('created_at', ''),
        'updated_at': issue.get('updated_at', ''),
        'comments': issue.get('comments', 0),
        'body': (issue.get('body') or '')[:500]
    })

with open('issues-data.json', 'w', encoding='utf-8') as f:
    json.dump(processed, f, ensure_ascii=False, indent=2)

print(f"\n数据就绪: {len(processed)} 个 open issues")
PYEOF
```

### Step 2: 生成 AI 分析 Prompt

数据采集完成后，**在当前会话中**提交以下分析任务给 Claude：

```
你是一个资深产品分析专家。请分析以下来自 GitCode 开源社区 euler-api-list 仓库的 {N} 个 open issue，完成主题聚类和优先级分析。

## 分析要求

1. **主题聚类**: 仔细阅读每条 issue 的标题和正文，将它们归类为 5-8 个核心诉求主题。每个主题命名清晰（中文），覆盖 issue 数尽量均衡，剩余零散诉求放入"其他工具与集成"。

2. **优先级判断**: 基于以下标准为每个主题给出 P0/P1/P2:
   - P0(高优): 跨多个社区反馈、阻塞交付流程、有明确工期要求、涉及安全或合规
   - P1(中优): 影响面较广但非阻塞、单社区集中反馈、用户体验明显受损
   - P2(普通): 零散诉求、单个用户反馈、无明确时间要求、纯建议类

3. **Issue 关联**: 每个主题下列举对应的 issue NUMBER（准确的 number 字段值）。

4. **一句话总结**: 每个主题用一句话概括核心诉求。

5. **AI 建议**: 每个主题给出 1-2 句可行动的建议。

## 输出格式

严格按以下 JSON 格式输出，不要输出其他内容，不要加 markdown 代码块标记:

{
  "analyzed_at": "ISO时间",
  "total_issues": {N},
  "category_count": {M},
  "categories": [
    {
      "theme": "主题名",
      "priority": "P0|P1|P2",
      "summary": "一句话总结",
      "ai_suggestion": "可行动建议",
      "issue_count": N,
      "issues": ["编号", "编号", ...]
    }
  ]
}

## Issue 数据

以下是全部 {N} 个 open issue 的数据，每条包含 number, title, body摘要, labels, type, reporter:

{逐条列出每个 issue 的关键信息}
```

### Step 3: 保存 AI 分析结果

Claude 输出 JSON 后，将其保存为 `ai-insights.json`：

```bash
cat > /home/wangsike/workspace/tmp/gitcode-dev/ai-insights.json << 'JSONEOF'
{Claude 输出的 JSON}
JSONEOF

python3 -c "import json; d=json.load(open('/home/wangsike/workspace/tmp/gitcode-dev/ai-insights.json')); print(f'OK: {len(d[\"categories\"])} categories, {d[\"total_issues\"]} issues')"
```

## 注意事项

- 数据采集使用 `gc issue list` CLI，需要已认证（`gc auth login`）
- AI 分析利用当前 Claude 会话执行，质量高于自动化 CLI 调用
- 输出 JSON 必须是有效 JSON，可被 Dashboard 直接 fetch 加载
- 分析完成后可 git push 更新 GitHub Pages
