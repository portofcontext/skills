---
name: portlang
description: >
  Master portlang - the environment-first agent framework. Use this skill when you need to:
  (1) Create and configure field.toml files for agent tasks,
  (2) Define boundaries and verifiers to control agent behavior,
  (3) Add custom tools (shell, Python, or MCP servers),
  (4) Debug agent failures using trajectories,
  (5) Optimize agent reliability with convergence testing,
  (6) Configure Code Mode for token-efficient operations,
  (7) Structure multi-layer verification patterns,
  (8) Analyze agent behavior across multiple runs.
  portlang manages environments, not loops. You define the search space; the agent finds the path.
license: MIT
---

# portlang Skill

## Core Concept

portlang treats agent behavior as **search through a conditioned space**. You don't script loops—you declare the search space:
- **Boundaries:** What the agent cannot do (enforced by sandbox)
- **Verifiers:** What success looks like (runtime reward signals)
- **Context budget:** Hard token ceiling
- **Environment:** What the agent can observe

The runtime executes the search. Every run produces a **trajectory** (complete event log).

## Prerequisites

Before running portlang fields:

1. **Install portlang:**
   ```bash
   git clone https://github.com/portofcontext/portlang
   cd portlang && cargo build --release
   ```

2. **Set API key** (choose one):
   ```bash
   # For Anthropic direct
   export ANTHROPIC_API_KEY=sk-ant-...

   # For OpenRouter
   export OPENROUTER_API_KEY=sk-or-v1-...
   ```

3. **Verify installation:**
   ```bash
   portlang init  # Check container support (macOS only)
   ```

**Model naming by provider:**
- Anthropic API: `anthropic/claude-sonnet-4.6`, `anthropic/claude-opus-4.5`
- OpenRouter: `anthropic/claude-3.5-sonnet`, `anthropic/claude-3-opus`
- Provider auto-detected from API key (use `ANTHROPIC_API_KEY` or `OPENROUTER_API_KEY`)

## Six Primitives

| Primitive | Purpose | Example |
|-----------|---------|---------|
| **Field** | Unit of work with constraints | `field.toml` configuration |
| **Environment** | What agent can see | `root = "./workspace"` |
| **Boundary** | Hard walls (sandbox-enforced) | `allow_write = ["*.py"]` |
| **Verifier** | Success criteria (injects feedback) | `pytest tests/ -v` |
| **Context Policy** | Token budget + limits | `max_tokens = 80000` |
| **Trajectory** | Complete event log | `~/.portlang/trajectories/` |

## Minimal field.toml

```toml
name = "my-task"
goal = "Create hello.py that prints 'Hello, World!'"

[model]
name = "anthropic/claude-sonnet-4.6"  # or "anthropic/claude-3.5-sonnet" for OpenRouter
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["hello.py"]

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 10

[[verifiers]]
name = "works"
command = "python hello.py 2>&1 | grep -q 'Hello, World!'"
trigger = "on_stop"
description = "Must print 'Hello, World!'"
```

## Essential Commands

```bash
portlang run field.toml              # Execute once
portlang check field.toml            # Validate configuration
portlang converge field.toml -n 10   # Run 10x, measure reliability
portlang list                        # Show trajectories
portlang replay <id>                 # Debug a run (interactive, use q to quit)
portlang diff <id-a> <id-b>          # Compare two runs
```

**Note:** `replay` is interactive - press `q` to quit, `n` for next step, `p` for previous.

## Key Patterns

### 1. Multi-Layer Verifiers (fail fast with precise feedback)

```toml
[[verifiers]]
name = "exists"
command = "test -f output.json"
trigger = "on_stop"
description = "output.json must exist"

[[verifiers]]
name = "valid-json"
command = "python -m json.tool output.json > /dev/null"
trigger = "on_stop"
description = "Must be valid JSON"

[[verifiers]]
name = "schema"
command = "./validate_schema.py output.json"
trigger = "on_stop"
description = "Must match schema"
```

Verifiers run in order, stop on first failure.

### 2. Scoped Boundaries (make bad actions impossible)

```toml
[boundary]
allow_write = ["output.json", "logs/*.txt"]  # Only these
allow_read = ["data/*.csv"]                  # Only input data
network = "deny"                             # No external calls
```

### 3. Custom Tools

**Shell tool:**
```bash
#!/bin/bash
# tools/word_count.sh
FILE="$1"
COUNT=$(wc -w "$FILE" | awk '{print $1}')
echo "{\"count\": $COUNT}"
```

```toml
[[tool]]
type = "shell"
script = "./tools/word_count.sh"
```

**Python tool:**
```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pandas"]
# ///

def execute(input: dict) -> dict:
    import pandas as pd
    # Process data
    return {"result": "..."}
```

```toml
[[tool]]
type = "python"
script = "./tools/processor.py"
```

**MCP server:**
```toml
[[tool]]
type = "mcp"
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
transport = "stdio"
```

### 4. Code Mode (for large data)

```toml
[code_mode]
enabled = true

[[tool]]
type = "python"
script = "./tools/data_tools.py"  # Exposes data ops
```

Agent writes TypeScript code that calls tools. Data stays outside context window.

## Debugging Workflow

1. **Run fails** → `portlang replay <id>` to see what happened
2. **Find failure point** → Check which verifier failed
3. **Non-determinism** → `portlang diff <id-a> <id-b>` to find divergence
4. **Optimize** → `portlang converge -n 10` to measure reliability

## Common Issues

**Budget exhausted:**
- Increase `max_tokens` or reduce `max_steps`
- Simplify `re_observation` commands
- Check for tool error loops

**Low convergence rate (<70%):**
- Strengthen verifiers (make expectations explicit)
- Tighten boundaries (restrict file access)
- Clarify goal prompt
- Lower temperature if too random

**Verifier always passes/fails:**
- Weak signal (>95% or <10% pass rate)
- Adjust verifier to provide useful feedback

## Helper Scripts

```bash
# Generate new field template
./scripts/new_field.sh my-task

# Validate field thoroughly
./scripts/validate_field.sh field.toml

# Analyze all trajectories for a field
python scripts/analyze_trajectories.py my-task
```

## Reference Documentation

For details, see:
- **reference/verifier_patterns.md** - 20 real-world verifier examples
- **reference/custom_tools.md** - Shell, Python, MCP guides
- **reference/trajectory_analysis.md** - Advanced debugging
- **reference/field_recipes.md** - 8 complete field.toml examples

## Core Principles

1. **Boundaries are topology, not policy** - Make bad actions impossible, not discouraged
2. **Verifiers are runtime reward signals** - Not post-hoc checks, they steer behavior
3. **Context is finite** - Hard ceiling, no magic compression
4. **Trajectories are data** - Replay, diff, analyze distributions
5. **Engineer the space, not the searcher** - Agent policy is opaque, environment is yours

---

*GitHub: https://github.com/portofcontext/portlang*
