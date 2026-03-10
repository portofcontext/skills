---
name: portlang
description: "Master portlang - the environment-first agent framework. Use when creating field.toml files, defining boundaries and verifiers, adding custom tools (shell, Python, MCP), debugging trajectories, measuring convergence, configuring structured JSON output with output_schema, running batch evals, viewing HTML trajectory dashboards, or analyzing agent behavior across runs. portlang manages environments not loops - you define the search space, the agent finds the path."
license: MIT
metadata:
  author: portofcontext
  version: 1.2.0
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

## field.toml Structure

All sections are optional unless marked (required).

```toml
name = "my-task"        # (required) identifier, used in trajectory storage
description = "..."     # human-readable summary

[model]                 # (required)
name = "anthropic/claude-sonnet-4.6"  # (required)
temperature = 0.5       # default: 0.5

[prompt]                # (required)
goal = "..."            # (required) initial task, enters context at step 0
system = "..."          # optional system prompt prepended to all interactions
re_observation = ["echo '=== workspace ===' && ls -1", ...]  # refresh context each step

[environment]           # optional; all fields have defaults
root = "./workspace"    # working dir (maps to /workspace in container)
packages = ["nodejs"]   # apt packages to install; list "uv" to get uv/pip
dockerfile = "./Dockerfile"  # custom Dockerfile (overrides packages)
image = "custom:tag"    # pre-built image (overrides dockerfile)

[boundary]              # optional
allow_write = ["*.py"]  # glob patterns for writable paths; default: none
network = "deny"        # "deny" | "allow"; default: allow
max_tokens = 150000     # hard ceiling on total context tokens
max_cost = "$2.00"      # hard ceiling on total cost
max_steps = 30          # hard ceiling on agent steps

[[verifier]]            # repeatable; zero or more
name = "..."            # (required)
command = "..."         # (required) exit 0 = pass, nonzero = fail
trigger = "on_stop"     # "on_stop" | "always" | "on_write"; default: on_stop
description = "..."     # injected into context on failure

[[tool]]                # repeatable; type = "python" | "shell" | "mcp"

[output_schema]         # optional; native TOML — JSON schema for structured output
```

## Minimal field.toml

```toml
name = "my-task"

[model]
name = "anthropic/claude-sonnet-4.6"

[prompt]
goal = "Create hello.py that prints 'Hello, World!'"

[environment]
root = "./workspace"

[boundary]
allow_write = ["hello.py"]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 10

[[verifier]]
name = "works"
command = "python hello.py 2>&1 | grep -q 'Hello, World!'"
trigger = "on_stop"
description = "Must print 'Hello, World!'"
```

## Essential Commands

```bash
portlang new field.toml              # Scaffold a new field.toml interactively
portlang run field.toml              # Execute once
portlang check field.toml            # Validate configuration
portlang converge field.toml -n 10   # Run N times, measure reliability
portlang eval ./examples/            # Run all fields in a directory
portlang list [field-name]           # List trajectories (--converged, --failed, --limit)
portlang replay <id>                 # Step through a trajectory (q=quit, n=next, p=prev)
portlang diff <id-a> <id-b>          # Compare two trajectories
portlang report <field-name>         # Adaptation analysis across runs
portlang view trajectory <id>        # Open trajectory as interactive HTML
portlang view eval ./examples/       # Open eval results dashboard
portlang view diff <id-a> <id-b>     # Open trajectory comparison HTML
portlang view field <field-name>     # Open field adaptation report HTML
portlang docs                        # Print full CLI reference as Markdown
```

Add `--html` to `replay`/`diff` for HTML output. Add `--no-open` to any `view` command to skip opening the browser. See **reference/CLI.md** for full flag details.

## Key Patterns

### 1. Structured Output (agent produces validated JSON)

Define the schema as native TOML under `[output_schema]`:

```toml
[output_schema]
type = "object"
required = ["status", "file_count", "files", "summary"]

[output_schema.properties.status]
type = "string"
enum = ["success", "failure"]

[output_schema.properties.file_count]
type = "integer"
minimum = 0

[output_schema.properties.files]
type = "array"

[output_schema.properties.files.items]
type = "string"

[output_schema.properties.summary]
type = "string"

# Validate with jq verifiers
[[verifier]]
name = "output-exists"
command = "test -f /workspace/output.json"
trigger = "on_stop"
description = "output.json must exist"

[[verifier]]
name = "status-success"
command = "jq -e '.status == \"success\"' /workspace/output.json"
trigger = "on_stop"
description = "Status must be success"
```

The agent writes `output.json` to `/workspace`. Schema violations are reported as failures.

### 2. Multi-Layer Verifiers (fail fast with precise feedback)

```toml
[[verifier]]
name = "exists"
command = "test -f output.json"
trigger = "on_stop"
description = "output.json must exist"

[[verifier]]
name = "valid-json"
command = "python -m json.tool output.json > /dev/null"
trigger = "on_stop"
description = "Must be valid JSON"

[[verifier]]
name = "tests-pass"
command = "./validate_schema.py output.json"
trigger = "on_stop"
description = "Must match schema"
```

Verifiers run in order, stop on first failure.

### 3. Scoped Boundaries

```toml
[boundary]
allow_write = ["output.json", "logs/*.txt"]
network = "deny"
max_tokens = 100000
max_cost = "$1.00"
max_steps = 20
```

### 4. Re-observation (keep context fresh)

```toml
[prompt]
goal = "..."
re_observation = [
  "echo '=== workspace ===' && ls -1 *.py *.txt 2>/dev/null | cat",
  "echo '=== tests ===' && python -m pytest --tb=no -q 2>&1 | tail -5",
]
```

Commands run before each agent step, injecting fresh state into context.

### 5. Custom Environment

```toml
[environment]
root = "./workspace"
packages = ["nodejs", "npm"]    # Install apt packages

# Or use a custom Dockerfile:
dockerfile = "./Dockerfile"

# Or a pre-built image:
image = "myregistry/myimage:latest"
```

### 6. Custom Tools

**Shell tool:**
```toml
[[tool]]
type = "shell"
name = "word_count"
description = "Count words in a file"
command = "wc {path}"
input_schema = '{"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}'
```

**Python tool (auto-schema from type hints):**
```python
# tools/calculator.py
def execute(expression: str) -> dict:
    """Evaluate a math expression and return the result."""
    return {"result": eval(expression)}
```

```toml
[[tool]]
type = "python"
file = "./tools/calculator.py"
function = "execute"  # schema auto-extracted from type hints; omit to expose all functions
```

**MCP server (stdio):**
```toml
[[tool]]
type = "mcp"
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
transport = "stdio"
```

**MCP server (HTTP/SSE):**
```toml
[[tool]]
type = "mcp"
name = "stripe"
url = "https://mcp.stripe.com"
transport = "http"
headers = { Authorization = "Bearer ${STRIPE_KEY}" }
```

### 7. Batch Evaluation

```bash
portlang eval ./examples/
portlang view eval ./examples/   # Open interactive HTML dashboard
```

Useful for regression testing after changes.

## Debugging Workflow

1. **Run fails** → `portlang replay <id>` to see what happened
2. **Find failure point** → Check which verifier failed and at which step
3. **Non-determinism** → `portlang diff <id-a> <id-b>` to find divergence
4. **Visual debugging** → `portlang view trajectory <id>` for HTML view
5. **Optimize** → `portlang converge -n 10` to measure reliability
6. **Patterns** → `portlang report <field-name>` for adaptation analysis

## Common Issues

**Budget exhausted:**
- Increase `max_tokens` or reduce `max_steps` in `[boundary]`
- Simplify `re_observation` commands
- Check for tool error loops

**Low convergence rate (<70%):**
- Strengthen verifiers (make expectations explicit)
- Tighten boundaries (restrict file access)
- Clarify goal in `[prompt]`
- Lower `temperature` (e.g., `temperature = 0.0`)

**Verifier always passes/fails:**
- Weak signal (>95% or <10% pass rate) — adjust verifier command

**Structured output not valid:**
- Add an explicit `[[verifier]]` to check `output.json`
- Ensure `[prompt].goal` names the required fields explicitly
- Use `temperature = 0.0` for consistent JSON output

## Reference Documentation

- **reference/CLI.md** - Full CLI reference (all commands and flags)
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
