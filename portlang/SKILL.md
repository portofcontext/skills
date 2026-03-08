---
name: portlang
description: >
portlang - the environment-first agent framework. Use this skill when you need to:
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

## Overview

**portlang** is an environment-first agent framework that treats agent behavior as search through a conditioned space. Unlike traditional agent frameworks that manage loops, portlang manages environments.

**Core philosophy:** Define the search space. The agent finds the path.

You declare:
- What success looks like (verifiers)
- What the agent can observe (environment)
- What the agent cannot do (boundaries)
- How much context is available (token budget)

The runtime executes the search and records the complete trajectory.

**When to use portlang:**
- Long-running tasks (multi-hour autonomous runs)
- Multi-file code changes with test verification
- Data processing pipelines
- Tasks requiring strong reliability guarantees
- Tasks where you need trajectory data for analysis

**Key insight:** The trained policy is opaque. The only variables you control are the context window and the environment. portlang gives you levers to engineer the search space.

## Six Primitives Quick Reference

| Primitive | Purpose | Example |
|-----------|---------|---------|
| **Field** | Self-contained unit of work with declared constraints | A refactoring task with file boundaries |
| **Environment** | What the agent can observe—filesystem, tools, network | Local workspace with read/write tools |
| **Boundary** | Hard walls enforced by sandbox—permissions, limits | `allow_write = ["*.py"]`, `network = "deny"` |
| **Verifier** | Success criteria that inject feedback into context | `pytest tests/ -v` runs on stop |
| **Context Policy** | Token budget (hard ceiling) and re-observation schedule | `max_tokens = 80000`, `max_steps = 30` |
| **Trajectory** | Complete event log—replayable, diffable, queryable | Stored in `~/.portlang/trajectories/` |

**Boundaries are topology, not policy.** Telling an agent "don't do X" is a suggestion. Making X impossible is a guarantee.

**Verifiers are reward signals, not post-hoc checks.** Test results enter the context window and reshape behavior at runtime.

## Creating Your First Field

### Step 1: Initialize a new field

```bash
cd my-project
portlang init my-task
```

Creates `field.toml` with basic structure.

### Step 2: Define the minimal field

```toml
name = "hello-world"
description = "Create a simple Python hello world program"

goal = """
Create a Python file called hello.py that prints "Hello, World!"
Stop once the file exists.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
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
name = "file-exists"
command = "test -f hello.py"
trigger = "on_stop"
description = "hello.py must exist"
```

### Step 3: Validate before running

```bash
portlang check field.toml
```

Checks for structural issues like uncovered mutation paths or unreachable verifiers.

### Step 4: Run the field

```bash
portlang run field.toml
```

The agent will:
1. Read the goal
2. Create hello.py
3. Stop
4. Verifier runs: `test -f hello.py`
5. If pass: trajectory marked as converged
6. Complete trajectory saved to `~/.portlang/trajectories/hello-world/`

### Step 5: Review the trajectory

```bash
# List recent trajectories
portlang list

# Replay step-by-step
portlang replay <trajectory-id>
```

## field.toml Configuration Deep Dive

### [model] Section

```toml
[model]
name = "anthropic/claude-sonnet-4.6"    # Model to use
temperature = 1.0                        # Sampling temperature
max_tokens = 4000                        # Max tokens per API call
```

**Supported models:**
- `anthropic/claude-sonnet-4.6`
- `anthropic/claude-opus-4.5`
- `openrouter/*` (any OpenRouter model)

### [environment] Section

```toml
[environment]
type = "local"              # Currently only "local" supported
root = "./workspace"        # Working directory for agent
```

The environment is isolated via Apple Container (macOS only). The agent operates in `/workspace` inside the container, which maps to the `root` path.

### [boundary] Section

Hard constraints enforced by the sandbox:

```toml
[boundary]
allow_write = ["*.py", "*.txt"]         # Glob patterns for writable files
allow_read = ["data/*.csv"]             # Optional: restrict reads
network = "deny"                        # Network policy: "deny" or "allow"
```

**Important:** Boundary violations are rejected at runtime. If the agent tries to write to a file not matching `allow_write`, the action is blocked and a rejection message enters the context window.

### [context] Section

Token budget and step limits:

```toml
[context]
max_tokens = 80000          # Hard token ceiling (not per-call, total)
max_cost = "$1.00"          # Hard cost ceiling
max_steps = 30              # Maximum number of agent steps
```

When `max_tokens` is reached, the run terminates with outcome `BudgetExhausted`. No magic compression.

### [[verifiers]] Section

Verifiers are reward signals that steer the search:

```toml
[[verifiers]]
name = "tests-pass"
command = "python -m pytest tests/ -v 2>&1"
trigger = "on_stop"
description = "All tests must pass"
```

**Fields:**
- `name`: Unique identifier
- `command`: Shell command to run
- `trigger`: When to run (see Verifier Patterns section)
- `description`: Human-readable expectation (injected into context on failure)

### Optional Sections

**re_observation** (re-observe environment periodically):

```toml
re_observation = [
    "echo '=== files ===' && ls -1 *.py 2>/dev/null | cat"
]
```

Runs before each agent step to keep context fresh.

**[code_mode]** (enable token-efficient code execution):

```toml
[code_mode]
enabled = true
```

See Code Mode section below.

**[[tool]]** (custom tools):

```toml
[[tool]]
type = "shell"
script = "./tools/word_count.sh"

[[tool]]
type = "python"
script = "./tools/analyzer.py"
```

See Custom Tools section below.

## Verifier Patterns

### Three Trigger Types

1. **on_stop**: Runs when agent signals completion
   ```toml
   [[verifiers]]
   name = "output-exists"
   command = "test -f output.json"
   trigger = "on_stop"
   description = "Output file must exist"
   ```

2. **on_write** (FUTURE): Runs after each file write
   ```toml
   # Not yet implemented
   [[verifiers]]
   name = "syntax-valid"
   command = "python -m py_compile {file}"
   trigger = "on_write"
   ```

3. **always** (FUTURE): Runs after every step
   ```toml
   # Not yet implemented
   [[verifiers]]
   name = "no-secrets"
   command = "./check_secrets.sh"
   trigger = "always"
   ```

**Current implementation:** Only `on_stop` is implemented. Use `on_stop` for all verifiers.

### Multi-Layer Verification Pattern

Verifiers run in order and stop on first failure. This gives precise feedback:

```toml
[[verifiers]]
name = "output-exists"
command = "test -f summary.json"
trigger = "on_stop"
description = "Output file must exist"

[[verifiers]]
name = "valid-json"
command = "python -m json.tool summary.json > /dev/null"
trigger = "on_stop"
description = "Output must be valid JSON"

[[verifiers]]
name = "correct-schema"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
assert 'revenue' in data, 'Missing revenue field'
assert isinstance(data['revenue'], (int, float)), 'Revenue must be numeric'
"
"""
trigger = "on_stop"
description = "JSON must have revenue field with numeric value"
```

**Pattern:** file exists → syntactically valid → semantically correct

**Why this works:** Early failures give the agent precise information about what went wrong, steering it toward correct solutions.

### Best Practices

1. **Descriptive descriptions:** The `description` field is injected into context on failure. Make it actionable.
   - Bad: `"Schema invalid"`
   - Good: `"JSON must have 'revenue' field with numeric value"`

2. **Progressive complexity:** Start with simple checks (file exists) before complex ones (schema validation)

3. **Exit codes matter:** Verifiers pass if exit code is 0, fail otherwise. Use `&&` and `||` carefully.

4. **Capture output:** Use `2>&1` to capture stderr:
   ```bash
   python -m pytest tests/ -v 2>&1
   ```

5. **Cover all mutations:** Every file in `allow_write` should be checked by at least one verifier.

## Custom Tools

portlang supports three types of custom tools:

### 1. Shell Tools

**Definition in field.toml:**

```toml
[[tool]]
type = "shell"
script = "./tools/word_count.sh"
```

**Script format (word_count.sh):**

```bash
#!/bin/bash
# Tool: word_count
# Description: Count words in a file
# Input schema: {"file": "string"}
# Output schema: {"count": "number"}

FILE=$1
wc -w "$FILE" | awk '{print "{\"count\": " $1 "}"}'
```

**How it works:**
- Agent calls tool with JSON input: `{"file": "data.txt"}`
- Runtime extracts parameters and passes as arguments
- Script outputs JSON
- Result enters context window

### 2. Python Tools

**Definition in field.toml:**

```toml
[[tool]]
type = "python"
script = "./tools/data_processor.py"
```

**Script format (data_processor.py):**

```python
#!/usr/bin/env python3
# /// script
# dependencies = [
#   "pandas",
#   "numpy",
# ]
# ///

def execute(input: dict) -> dict:
    """
    Process data and return statistics.

    Input: {"data": [1, 2, 3, 4, 5]}
    Output: {"mean": 3.0, "sum": 15}
    """
    import numpy as np
    data = input.get("data", [])
    return {
        "mean": float(np.mean(data)),
        "sum": int(np.sum(data))
    }
```

**Format:**
- PEP 723 inline dependencies (between `# ///` markers)
- `execute(input: dict) -> dict` signature required
- Return JSON-serializable dict

### 3. MCP Servers

**MCP (Model Context Protocol)** is Anthropic's standard for connecting LLMs to data sources.

**Finding MCP servers:**
- https://github.com/modelcontextprotocol/servers
- npm registry: search "mcp-server"
- GitHub: search "mcp server"

**Configuration example (stdio transport):**

```toml
[[tool]]
type = "mcp"
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
transport = "stdio"
```

**Configuration example (HTTP transport):**

```toml
[[tool]]
type = "mcp"
name = "github"
url = "https://mcp-server-github.com"
transport = "http"
```

**Debugging MCP connections:**

```bash
# Test stdio MCP server manually
npx -y @modelcontextprotocol/server-filesystem /workspace

# Check portlang logs
portlang run field.toml --verbose
```

**Common MCP servers:**
- `@modelcontextprotocol/server-filesystem`: File operations
- `@modelcontextprotocol/server-github`: GitHub API
- `@modelcontextprotocol/server-postgres`: Database queries

## Code Mode

**What is Code Mode?**

Code Mode allows the agent to write and execute TypeScript code that processes data outside the context window. This is critical for tasks involving large datasets.

**When to use Code Mode:**
- Processing files too large to fit in context (>10k tokens)
- Filtering, sorting, or transforming data
- Batch operations on many files
- Any task where reading data into context would waste tokens

**How it works:**
1. You enable Code Mode in field.toml
2. You define Python tools that expose data operations
3. Agent writes TypeScript code calling those tools
4. Code executes in sandbox, results summarized in context

**Example configuration:**

```toml
[code_mode]
enabled = true

[[tool]]
type = "python"
script = "./tools/data_tools.py"
```

**Example Python tool (data_tools.py):**

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pandas"]
# ///

def execute(input: dict) -> dict:
    """Load and filter user data."""
    import pandas as pd
    operation = input.get("operation")

    if operation == "load":
        df = pd.read_json("users.json")
        return {"count": len(df)}

    elif operation == "filter":
        df = pd.read_json("users.json")
        filtered = df[df["age"] > input["min_age"]]
        filtered.to_json("output.json", orient="records")
        return {"count": len(filtered)}
```

**Example agent behavior with Code Mode:**

Without Code Mode:
- Agent reads entire users.json (100k tokens)
- Filters in context
- Writes output.json
- Total tokens: ~100k

With Code Mode:
- Agent writes TypeScript: `filter({min_age: 30})`
- Tool processes data outside context
- Result: `{count: 58}`
- Total tokens: ~2k

**Current status:** Code Mode is 80% complete (Phase 4).

## Debugging with Trajectories

Every run produces a complete trajectory: the event log of all steps, actions, responses, and verifiers.

### List Trajectories

```bash
portlang list
```

Shows recent trajectories with ID, field name, outcome, and timestamp.

### Replay a Trajectory

```bash
portlang replay <trajectory-id>
```

Step through the trajectory interactively. At each step see:
- Action taken
- Environment response
- Verifier results (if any)
- Running token count
- Context window (reconstructed)

**Use cases:**
- Understand why a run failed
- See what the agent observed at each step
- Identify where the agent went off track

### Diff Two Trajectories

```bash
portlang diff <id-a> <id-b>
```

Compares two trajectories structurally and identifies the first divergence point.

**Output:**
- Aligned actions by step
- First point where runs diverged
- What each run did differently

**Use case:** Non-determinism debugging. If the same field produces different outcomes, diff shows where behavior forked.

### Common Debugging Workflow

1. Run fails: `portlang run field.toml`
2. Replay to find failure point: `portlang replay <id>`
3. Look at verifier feedback: which layer failed?
4. Adjust verifier or boundary
5. Run again
6. Compare with previous run: `portlang diff <old-id> <new-id>`

**Pro tip:** Use `portlang check field.toml` before running to catch structural issues.

## Convergence Testing

Agent systems are non-deterministic. You need to reason about distributions, not individual runs.

### Run N Times

```bash
portlang converge field.toml -n 10
```

Runs the field 10 times and reports:
- Convergence rate (% of runs that passed all verifiers)
- Token usage distribution (median, p90, p99)
- Cost distribution
- Step count distribution
- Adaptation report (which tools correlate with success)

**Example output:**

```
Convergence: 8/10 (80%)
Tokens: median=12.5k, p90=18.2k, p99=22.1k
Cost: median=$0.42, p90=$0.58, p99=$0.71
Steps: median=8, p90=12, p99=15

Adaptation:
- Tool 'read' used in 100% of runs
- Tool 'write' used in 80% of runs (100% of successes)
- Verifier 'tests-pass' failed in 20% of runs
```

### Interpret Results

**High convergence (>90%):** Field is reliable
**Medium convergence (70-90%):** Field works but has variance. Check diff to find divergence patterns.
**Low convergence (<70%):** Field definition needs work. Check:
- Are verifiers too strict?
- Is token budget too tight?
- Are boundaries too restrictive?
- Is the goal ambiguous?

### Generate Adaptation Report

```bash
portlang report field.toml
```

Analyzes all historical trajectories for this field and surfaces:
- Tool usage patterns
- Budget utilization trends
- Verifier pass rates
- Common divergence points

**Use this to optimize fields:** Remove unused tools, adjust token budgets, strengthen weak verifiers.

## Common Patterns & Best Practices

### Pattern 1: Progressive Verification

Start simple, add complexity:

```toml
[[verifiers]]
name = "output-exists"
command = "test -f result.json"
trigger = "on_stop"
description = "result.json must exist"

[[verifiers]]
name = "valid-json"
command = "python -m json.tool result.json > /dev/null"
trigger = "on_stop"
description = "result.json must be valid JSON"

[[verifiers]]
name = "schema-check"
command = "./validate_schema.sh result.json"
trigger = "on_stop"
description = "result.json must match expected schema"

[[verifiers]]
name = "data-integrity"
command = "./check_data_integrity.py result.json"
trigger = "on_stop"
description = "All data relationships must be valid"
```

### Pattern 2: Scoped Boundaries

Minimize write access:

```toml
# Bad: Too permissive
[boundary]
allow_write = ["**/*"]

# Good: Specific files
[boundary]
allow_write = ["output.json", "logs/*.txt"]
```

### Pattern 3: Re-observation for Long Tasks

Keep context fresh without bloating:

```toml
re_observation = [
    "echo '=== Current files ===' && ls -1 *.py 2>/dev/null | cat",
    "echo '=== Git status ===' && git status --short"
]
```

Runs before each step. Shows the agent what changed without re-reading full files.

### Pattern 4: Token Budget Planning

Estimate before running:

- Goal prompt: ~500 tokens
- Re-observation per step: ~100 tokens
- Max steps: 30
- Estimated re-observation total: 30 × 100 = 3k
- Tool responses: ~200 tokens/step × 30 = 6k
- Total estimate: 500 + 3k + 6k = ~10k minimum

Set `max_tokens = 80000` for safety margin.

**Rule of thumb:** Budget should be 5-8x your estimate to handle unexpected paths.

---

## Additional Resources

- **Field examples:** See `reference/field_recipes.md` for complete working examples
- **Verifier patterns:** See `reference/verifier_patterns.md` for 15+ real-world verifier examples
- **Custom tools guide:** See `reference/custom_tools.md` for detailed tool development
- **Trajectory analysis:** See `reference/trajectory_analysis.md` for advanced debugging techniques

## Helper Scripts

This skill includes helper scripts in `scripts/`:

- `new_field.sh`: Interactive field template generator
- `validate_field.sh`: Enhanced validation beyond `portlang check`
- `analyze_trajectories.py`: Multi-trajectory statistical analysis

Usage:
```bash
# Generate new field
./scripts/new_field.sh my-task

# Validate field with extra checks
./scripts/validate_field.sh field.toml

# Analyze all trajectories for a field
python scripts/analyze_trajectories.py my-field-name
```

---

## Quick Reference

**Essential Commands:**
```bash
portlang run field.toml          # Execute once
portlang check field.toml        # Validate configuration
portlang list                    # Show recent trajectories
portlang replay <id>             # Step through trajectory
portlang diff <id-a> <id-b>      # Compare two runs
portlang converge field.toml -n 10  # Run 10 times, measure reliability
portlang report field.toml       # Adaptation analysis
portlang eval <dir>              # Run all fields in directory
```

**Key Principles:**
1. Boundaries are topology, not policy
2. Verifiers are runtime reward signals
3. Context is a finite resource (hard ceiling)
4. Trajectories are data (replay, diff, analyze)
5. Agent behavior is search (engineer the space, not the searcher)

**Getting Help:**
- GitHub: https://github.com/portofcontext/portlang
- Documentation: See README.md in portlang repo
- Examples: See `examples/` directory

---

*This skill is part of the Port of Context Skills repository.*
