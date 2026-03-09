---
name: portlang
description: "Master portlang - the environment-first agent framework. Use when creating field.toml files, defining boundaries and verifiers, adding custom tools (shell, Python, MCP), debugging trajectories, measuring convergence, configuring structured JSON output with output_schema, running batch evals, viewing HTML trajectory dashboards, or analyzing agent behavior across runs. portlang manages environments not loops - you define the search space, the agent finds the path."
license: MIT
metadata:
  author: portofcontext
  version: 1.1.0
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
   export ANTHROPIC_API_KEY=sk-ant-...
   export OPENROUTER_API_KEY=sk-or-v1-...
   ```

3. **Verify installation:**
   ```bash
   portlang init  # Check container support (macOS only)
   ```

**Model naming by provider:**
- Anthropic API: `anthropic/claude-sonnet-4.6`, `anthropic/claude-opus-4.5`
- OpenRouter: `anthropic/claude-3.5-sonnet`, `anthropic/claude-3-opus`
- Provider auto-detected from API key

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
name = "works"
command = "python hello.py 2>&1 | grep -q 'Hello, World!'"
trigger = "on_stop"
description = "Must print 'Hello, World!'"
```

## Essential Commands

### Execution

```bash
portlang run field.toml              # Execute once
portlang check field.toml            # Validate configuration
portlang converge field.toml -n 10   # Run 10x, measure reliability
portlang eval ./examples/            # Run all fields in a directory
portlang eval ./examples/ --html     # Eval with HTML dashboard output
```

### Trajectory Inspection

```bash
portlang list                          # Show all trajectories
portlang list my-task                  # Filter by field name
portlang list --converged --limit 5    # Last 5 successful runs
portlang list --failed                 # Only failed runs
portlang replay <id>                   # Debug a run (interactive)
portlang replay <id> --format json     # JSON output
portlang replay <id> --html            # HTML output
portlang diff <id-a> <id-b>            # Compare two runs
portlang diff <id-a> <id-b> --html     # HTML diff view
portlang report <field-name>           # Adaptation analysis across runs
portlang report my-task --converged    # Report on successful runs only
```

**Note:** `replay` is interactive - press `q` to quit, `n` for next step, `p` for previous.

### HTML Visualization

```bash
portlang view trajectory <id>          # Open trajectory as interactive HTML
portlang view eval ./examples/         # Open eval dashboard
portlang view diff <id-a> <id-b>       # Open trajectory comparison
portlang view field <field-name>       # Open field adaptation report
```

## Key Patterns

### 1. Structured Output (agent produces validated JSON)

```toml
output_schema = '''
{
  "type": "object",
  "required": ["status", "score", "details"],
  "properties": {
    "status": {"type": "string", "enum": ["success", "failure"]},
    "score": {"type": "integer", "minimum": 0, "maximum": 100},
    "details": {"type": "array", "items": {"type": "string"}}
  }
}
'''

# Verifiers can validate structured output with jq
[[verifiers]]
name = "output-exists"
command = "test -f /workspace/output.json"
trigger = "on_stop"
description = "output.json must exist"

[[verifiers]]
name = "status-success"
command = "jq -e '.status == \"success\"' /workspace/output.json"
trigger = "on_stop"
description = "Status must be success"
```

The agent writes `output.json` to `/workspace`. The schema is enforced at runtime—schema violations are reported as failures.

### 2. Multi-Layer Verifiers (fail fast with precise feedback)

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

### 3. Scoped Boundaries (make bad actions impossible)

```toml
[boundary]
allow_write = ["output.json", "logs/*.txt"]  # Only these
allow_read = ["data/*.csv"]                  # Only input data
network = "deny"                             # No external calls
```

### 4. Re-observation (keep context fresh)

```toml
re_observation = [
  "echo '=== workspace ===' && ls -1 *.py *.txt 2>/dev/null | cat",
  "echo '=== test status ===' && python -m pytest --tb=no -q 2>&1 | tail -5",
]
```

These commands run before each agent step, injecting fresh state into context.

### 5. Custom Tools

**Shell tool (command template):**
```toml
[[tool]]
name = "word_count"
type = "shell"
description = "Count words in a file"
command = "wc {path}"
input_schema = '{"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}'
```

**Python tool (auto-schema from type hints):**
```python
# tools/calculator.py
def execute(expression: str) -> dict:
    """Evaluate a math expression and return the result."""
    result = eval(expression)
    return {"result": result}
```

```toml
[[tool]]
type = "python"
script = "./tools/calculator.py"
function = "execute"  # Schema auto-extracted from type hints
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

### 6. Batch Evaluation

Run all fields in a directory and get aggregate statistics:

```bash
portlang eval ./examples/
portlang view eval ./examples/   # Open interactive HTML dashboard
```

Useful for regression testing or measuring overall suite reliability after changes.

## Debugging Workflow

1. **Run fails** → `portlang replay <id>` to see what happened
2. **Find failure point** → Check which verifier failed and at which step
3. **Non-determinism** → `portlang diff <id-a> <id-b>` to find divergence
4. **Visual debugging** → `portlang view trajectory <id>` for HTML view
5. **Optimize** → `portlang converge -n 10` to measure reliability
6. **Patterns** → `portlang report <field-name>` for adaptation analysis

## Common Issues

**Budget exhausted:**
- Increase `max_tokens` or reduce `max_steps`
- Simplify `re_observation` commands
- Check for tool error loops

**Low convergence rate (<70%):**
- Strengthen verifiers (make expectations explicit)
- Tighten boundaries (restrict file access)
- Clarify goal prompt
- Lower `temperature` for more deterministic behavior (e.g., `temperature = 0.0`)

**Verifier always passes/fails:**
- Weak signal (>95% or <10% pass rate)
- Adjust verifier to provide useful feedback

**Structured output not valid:**
- Add an explicit verifier to check schema
- Ensure goal references the required fields by name
- Use `temperature = 0.0` for more consistent JSON output

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
