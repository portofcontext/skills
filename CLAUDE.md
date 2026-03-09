# Skill Writing Guidelines

## Structure

Every skill is a folder containing:
- `SKILL.md` (required) — instructions with YAML frontmatter
- `scripts/` (optional) — executable code
- `references/` (optional) — docs loaded on demand
- `assets/` (optional) — templates, fonts, icons

No `README.md` inside the skill folder. All docs go in `SKILL.md` or `references/`.

## YAML Frontmatter

```yaml
---
name: kebab-case-name
description: What it does and when to use it. Include trigger phrases users would say.
license: MIT
metadata:
  author: Name
  version: 1.0.0
---
```

**name:** kebab-case only. No spaces, no capitals, no underscores.

**description:** Must include BOTH what it does AND when to use it. Under 1024 chars. No XML (`<` `>`). Include specific phrases users would say. Bad: "Helps with projects." Good: "Manages Linear sprint workflows. Use when user mentions 'sprint', 'Linear tasks', or asks to 'create tickets'."

**Forbidden:** XML angle brackets anywhere in frontmatter. Names starting with "claude" or "anthropic".

## Progressive Disclosure

- Frontmatter: always loaded, just enough to trigger
- `SKILL.md` body: loaded when skill is relevant
- `references/`: loaded only when needed

Keep `SKILL.md` under ~5,000 words. Move detail to `references/`.

## Instructions

Be specific and actionable:
- ✅ `Run python scripts/validate.py --input {filename}`
- ❌ `Validate the data before proceeding`

Include: step-by-step workflow, examples, error handling, references to bundled files.

For critical validations, use a script rather than language instructions. Code is deterministic; language isn't.

## Testing

**Triggering:** Run 10–20 test queries. 90% of relevant ones should auto-load the skill. Test that unrelated queries don't trigger it.

**Undertriggering fix:** Add more trigger phrases and keywords to the description.

**Overtriggering fix:** Add negative triggers. Example: `Do NOT use for simple data exploration (use data-viz skill instead).`

**Functional:** Same task with/without skill — compare tool calls, tokens, errors.

## Common Patterns

**Sequential workflow:** Explicit step ordering with dependencies and validation between steps.

**Multi-MCP coordination:** Clear phase separation, data passing between services, centralized error handling.

**Iterative refinement:** Draft → validate → refine loop with explicit quality criteria and stop condition.

**Context-aware selection:** Decision tree to choose the right tool/approach based on input characteristics.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Skill won't upload | Check `SKILL.md` exact casing; validate YAML delimiters `---` |
| Doesn't trigger | Revise description — add specific trigger phrases |
| Triggers too often | Add negative triggers; narrow scope |
| MCP calls fail | Test MCP independently first: "Use [Service] MCP to fetch my projects" |
| Instructions ignored | Put critical rules at top; use numbered lists; move detail to `references/` |
| Slow / degraded | Move docs to `references/`; keep `SKILL.md` under 5k words |

## Folder Naming

`kebab-case` only. Must match the `name` field in frontmatter.
