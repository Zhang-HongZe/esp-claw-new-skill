---
{
  "name": "turtle-soup-creator",
  "description": "Create a 海龟汤/turtle soup lateral-thinking puzzle with 汤面、汤底、提示线索和主持人备注, and save it as a Markdown file when the user asks.",
  "metadata": {
    "cap_groups": [
      "cap_files"
    ],
    "manage_mode": "readonly"
  }
}
---

# 海龟汤文案创作

Use this skill when the user asks to 创作海龟汤, 写海龟汤文案, 出一道海龟汤, create a turtle soup puzzle, or design a lateral-thinking riddle with a surface story and hidden truth.

This is a document-first skill. Read only the bundled references that help the current request:

- Read `{CUR_SKILL_DIR}/references/logic-checklist.md` before final output. This self-check is mandatory.
- Read `{CUR_SKILL_DIR}/references/genre-guide.md` when the user gives or asks for theme, tone, or genre guidance.
- Read `{CUR_SKILL_DIR}/references/templates.md` when you want a reusable structure or a faster first draft.
- Read `{CUR_SKILL_DIR}/references/variant-rules.md` for 变格, 超自然, 科幻, 规则怪谈, or other non-realistic setups.
- Read `{CUR_SKILL_DIR}/references/host-manual.md` when the user also wants 主持话术, game-flow control, or online/party hosting notes.
- Read `{CUR_SKILL_DIR}/references/classic-cases.md` when you need inspiration, benchmark examples, or reversal patterns.
- Read `{CUR_SKILL_DIR}/references/faq.md` when the draft has quality issues or the user asks how to improve a puzzle.
- Read `{CUR_SKILL_DIR}/references/progression-guide.md` for coaching, practice plans, or long-term learning advice.
- Read `{CUR_SKILL_DIR}/references/collaboration-guide.md` for multi-person or workshop-style creation.

## Core Rules

1. Resolve four inputs before writing: theme, difficulty, type, and special constraints.
2. If the user does not care, default to `悬疑 / 中等 / 本格` and no extra constraints.
3. Write 汤底 first, then derive 汤面 by hiding key information while keeping fair clues.
4. Keep 汤面 concise: usually 2-5 sentences and about 50-150 Chinese characters.
5. Every abnormal detail in 汤面 must have a matching explanation in 汤底.
6. Always provide 3 progressive hints and short host notes.
7. Avoid gore, sexual content, hate, real-person harm, or shock value without logic.
8. Do not rely on niche professional knowledge or pure wordplay as the only solution.
9. Before finalizing, self-check against `{CUR_SKILL_DIR}/references/logic-checklist.md` and repair any logic hole.
10. If the user wants a file, save the final Markdown with `write_file` only after you know an absolute writable path under the DATA root. Do not assume `/fatfs`, do not use relative paths, and do not invent unknown mount points.

## Required Inputs

Ask briefly for:

- `主题偏好`: `恐怖 / 悬疑 / 温情 / 搞笑 / 科幻 / 日常 / 爱情 / 其他`
- `难度等级`: `简单 / 中等 / 困难`
- `类型`: `本格 / 变格`
- `特殊要求`: open text such as `避免血腥`, `要感人`, `要双重反转`

If the user already gave enough constraints, do not re-ask all of them.

## Creation Workflow

1. Resolve the inputs and any safety or style constraints.
2. If the type is `变格`, read `{CUR_SKILL_DIR}/references/variant-rules.md`.
3. If the theme or structure is unclear, read `{CUR_SKILL_DIR}/references/genre-guide.md` or `{CUR_SKILL_DIR}/references/templates.md`.
4. Design the core reversal first and write a complete 汤底 with background, event flow, motive, and clue mapping.
5. Derive a concise 汤面 that looks puzzling on the surface but still contains fair clues.
6. Write 3 hints in light, medium, and heavy order.
7. Add host notes, including likely yes/no/irrelevant questions, common wrong paths, and pacing suggestions.
8. Run the logic self-check and fix issues before output.
9. Return the final Markdown. Save it only when requested or when a valid save path is already known.

## Markdown Output Template

```markdown
# [海龟汤标题]

**主题**：[主题] | **难度**：[简单/中等/困难] | **类型**：[本格/变格]

---

## 汤面
[谜面描述，2-5句话]

---

## 汤底

### 故事背景
[背景介绍]

### 事件经过
[完整经过，包含起因、发展、结果]

### 关键线索解释
- **[汤面线索A]**：[对应解释]
- **[汤面线索B]**：[对应解释]

---

## 提示线索
1. **轻度**：[指向汤面细节的提示]
2. **中度**：[建立信息联系的提示]
3. **重度**：[接近核心真相的提示]

---

## 推理要点

| 玩家可能提问 | 主持人回答 | 推理作用 |
|-------------|-----------|----------|
| [关键问题1] | [是/否/无关] | [引导方向说明] |
| [关键问题2] | [是/否/无关] | [排除误导说明] |
| [关键问题3] | [是/否/无关] | [接近真相说明] |

---

## 主持人备注

### 回答规范
| 玩家提问类型 | 主持人回应 |
|-------------|-----------|
| 直接相关 | 是 / 否 |
| 部分相关 | 拆分回答 |
| 无关问题 | 无关 |
| 开放式 | 引导具体化 |
| 复合问题 | 要求拆分 |

### 节奏建议
- 5分钟无进展：[给出轻度提示的方式]
- 10分钟无进展：[给出中度提示的方式]
- 15分钟无进展：[给出重度提示的方式]
- 常见误区：[玩家容易跑偏的方向]
- 接近真相时：[如何让玩家复述完整经过]
```

## File Saving Flow

When a file is requested:

1. Choose a filename like `海龟汤_[主题]_[难度].md`.
2. If the user already supplied an absolute device path, use it directly.
3. Otherwise ask for a save path or inspect storage with `list_dir` to find an existing writable directory under the DATA root.
4. Use `write_file` with the full Markdown content.
5. Report the saved path or the exact file-tool error.

Example `write_file` input:

```json
{
  "path": "<user_provided_absolute_path>/海龟汤_悬疑_中等.md",
  "content": "# ..."
}
```

## Recommended Flow

1. Gather or infer theme, difficulty, type, and constraints.
2. Read only the bundled references needed for this request.
3. Draft 汤底 before 汤面.
4. Self-check with the logic checklist.
5. Output the final Markdown.
6. If the user asked to save it, resolve a writable absolute path and call `write_file`.
7. If `write_file` fails, report the error directly and keep the Markdown in the reply.
