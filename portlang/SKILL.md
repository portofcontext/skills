---
name: portlang
description: "portlang - the environment-first agent framework. Use when working with .field files, defining boundaries and verifiers, adding custom tools (shell, Python, MCP), debugging trajectories, measuring convergence, configuring structured JSON output with output_schema, running batch evals, viewing HTML trajectory dashboards, or analyzing agent behavior across runs. portlang manages environments not loops - you define the search space, the agent finds the path."
license: MIT
metadata:
  author: portofcontext
  version: 1.2.9
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

portlang currently only runs on apple devices.
Before running portlang fields:

1. **Install portlang:**
```bash
brew tap portofcontext/homebrew-tap
brew install portlang
```

2. **Set API key** (choose one):
```bash
export ANTHROPIC_API_KEY=sk-ant-...
export OPENROUTER_API_KEY=sk-or-v1-...
```

3. **Verify installation:**
```bash
portlang init  # Check container support
```

4. **Install the VS Code extension** (recommended): Search for **"portlang"** in the VS Code extension marketplace and install it. Provides LSP support — syntax highlighting, validation, and autocompletion for `.field` files.

**Model naming by provider:**
- Anthropic API: `anthropic/claude-sonnet-4.6`, `anthropic/claude-opus-4.5`
- OpenRouter: `anthropic/claude-3.5-sonnet`, `anthropic/claude-3-opus`, anything on openrouter that support tool calling
- Provider auto-detected from API key

## Field File Structure

Fields use the `.field` extension (preferred) or `.toml` — both are supported. All sections are optional unless marked (required). Fields marked `"inherit"` pull their value from a parent field one directory up (auto-detected from `../*.field`).

```toml
name = "my-task"        # (required) identifier, used in trajectory storage
description = "..."     # human-readable summary

[vars]                  # optional; declare {{ var_name }} template variables
# customer_id = { required = true, description = "Salesforce account ID" }
# region = { required = false, default = "us-east-1", description = "AWS region" }

[model]                 # (required), or: model = "inherit"
name = "anthropic/claude-sonnet-4.6"  # (required)
temperature = 0.5       # default: 0.5

[prompt]                # (required)
goal = "..."            # (required) initial task; supports {{ var }} templates
system = "..."          # optional system prompt; supports {{ var }} templates
re_observation = ["echo '=== workspace ===' && ls -1", ...]  # refresh context each step

[environment]           # optional; all fields have defaults
root = "./workspace"    # working dir (maps to /workspace in container)
packages = ["nodejs"]   # apt packages to install; list "uv" to get uv/pip
dockerfile = "./Dockerfile"  # custom Dockerfile (overrides packages)
image = "custom:tag"    # pre-built image (overrides dockerfile)

[boundary]              # optional, or: boundary = "inherit"
allow_write = ["*.py"]  # glob patterns for writable paths; default: none
network = "deny"        # "deny" | "allow"; default: allow
max_tokens = 150000     # hard ceiling on total context tokens
max_cost = "$2.00"      # hard ceiling on total cost (must be quoted string with $)
max_steps = 30          # hard ceiling on agent steps
bash = true             # enable built-in bash tool; default: true
output_schema = """{ ... }"""  # optional; JSON schema string for structured output

tools = "inherit"       # optional; inherit [[tool]] list from parent instead of defining inline

[[tool]]                # repeatable; type = "python" | "shell" | "mcp"; bash/glob/write are built-in defaults

# Shell verifier (default when type is omitted):
[[verifier]]
type = "shell"          # default; type can be omitted for shell verifiers
name = "..."            # (required)
command = "..."         # shell command; exit 0 = pass, nonzero = fail; supports {{ var }} templates
trigger = "on_stop"     # "on_stop" | "always" | "on_tool:<tool_name>"; default: on_stop
description = "..."     # injected into context on failure

# Levenshtein verifier (normalized edit distance):
[[verifier]]
type = "levenshtein"
name = "..."
file = "output.txt"     # optional; omit to use output_schema structured output
expected = "..."        # reference string; supports {{ var }} templates
threshold = 0.9         # similarity [0.0–1.0] required to pass; default: 1.0

# Semantic similarity verifier (cosine via embeddings):
[[verifier]]
type = "semantic"
name = "..."
file = "output.txt"     # optional; omit to use output_schema structured output
expected = "..."        # reference string to embed and compare; supports {{ var }} templates
threshold = 0.85        # cosine similarity [0.0–1.0]; default: 0.8
embedding_model = "bge-small-en-v1.5"  # local model (~67 MB, downloaded once)
# embedding_url = "https://..."  # use OpenAI-compatible endpoint instead

# Tool call verifier (inspect or require a specific tool call):
[[verifier]]
type = "tool_call"
name = "..."
tool = "bash"           # (required for on_stop) assert this tool was called
field = "/input/path"   # optional; JSON pointer into {input: {...}, output: "..."}
matches = "^[a-z]+"    # optional; regex the field value must match
not_matches = "^/etc"  # optional; regex the field value must NOT match
```

## Minimal Field File

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
portlang new task.field             # Scaffold a new field file (.field preferred; .toml also supported)
portlang new -i                      # Interactive step-by-step field creation
portlang run task.field             # Execute once (native runner, default)
portlang run task.field --dry-run   # Validate field without running (parse, check vars, show config)
portlang run task.field -n 10       # Run N times and report convergence reliability
portlang run task.field --runner claude-code  # Use Claude Code as agent loop
portlang run task.field --var k=v   # Pass a template variable (repeatable)
portlang run task.field --vars p.json  # Pass variables from a JSON file
portlang run task.field --input ./data.csv   # Stage a file into the workspace before the agent starts
portlang run task.field --input '{"id":"123"}'  # Stage inline JSON as portlang_input.json
portlang list [field-name]           # List trajectories (--converged, --failed, --limit)
portlang eval run ./examples/        # Run all fields in a directory
portlang eval run ./examples/ --runner claude-code  # Eval suite using Claude Code runner
portlang eval run ./examples/ --resume <id>   # Resume a previous eval, skipping fields that already passed
portlang eval list [dir]             # List eval runs (--limit)
portlang eval view <id-or-dir>       # Open eval results dashboard (by run ID or directory)
portlang view trajectory <id>        # Open trajectory as interactive HTML
portlang view trajectory <id> --format text  # Replay trajectory step-by-step in terminal
portlang view diff <id-a> <id-b>     # Open trajectory comparison HTML
portlang view field <field-name>     # Open field adaptation report HTML
portlang docs                        # Print CLI reference as Markdown
```

Add `--no-open` to any `view` command to skip opening the browser. See **reference/CLI.md** for full flag details.

## Key Patterns

### 1. Field Inheritance (shared model/boundary/tools across a suite)

If a `*.field` file exists one directory up, a child field can inherit from it automatically:

```toml
# parent/parent.field — shared config for all child fields
name = "parent"

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 0.5

[boundary]
network = "deny"
max_tokens = 100000
max_cost = "$1.00"
max_steps = 20

[[tool]]
type = "python"
file = "./tools/shared_utils.py"
```

```toml
# parent/task-a/task.field — child; inherits from ../parent.field
name = "task-a"
model = "inherit"
boundary = "inherit"
tools = "inherit"

[prompt]
goal = "Do task A using the shared tools."
```

Inheritance eliminates duplication across eval suites. Override any section by defining it inline.

### 2. Template Variables (parameterize a field for reuse)

Declare variables in `[vars]`, use `{{ name }}` anywhere in goal/system/re_observation/verifier commands, supply at runtime with `--var`:

```toml
[vars]
currency = { required = false, default = "usd", description = "Currency to report" }

[prompt]
goal = "Get the account balance and return amounts in {{ currency }}."

[[verifier]]
name = "correct-currency"
type = "tool_call"
tool = "bash"
trigger = "on_stop"
description = "Agent must have run bash"
```

```bash
portlang run task.field --var currency=gbp
portlang run task.field --vars params.json   # bulk vars from file
portlang run task.field --input ./data.csv   # stage input file into workspace
```

`--input` with a file copies it to the workspace root. `--input '{"key":"val"}'` writes `portlang_input.json`. Use `re_observation` to surface the file contents to the agent each step.

### 3. Structured Output (agent produces validated JSON)

Define `output_schema` inside `[boundary]` as a JSON string. Schema validation is automatic — no separate verifier needed:

```toml
[boundary]
allow_write = ["output.json"]
output_schema = '''
{
  "type": "object",
  "required": ["status", "count"],
  "properties": {
    "status": {"type": "string", "enum": ["success", "failure"]},
    "count": {"type": "integer", "minimum": 0}
  }
}
'''
```

portlang validates the output against the schema, writes `output.json` to `/workspace`, and reports schema violations as failures. Add `[[verifier]]` entries only for additional business logic checks beyond schema conformance. Typed verifiers (`levenshtein`, `semantic`) can omit `file` to validate against the structured output directly.

### 4. Multi-Layer Verifiers (fail fast with precise feedback)

Layer verifiers from coarse to fine — each one assumes the previous passed:

```toml
[[verifier]]
name = "compiled"
command = "python script.py 2>/dev/null"
trigger = "on_stop"
description = "script.py must run without errors"

[[verifier]]
name = "correct-output"
type = "levenshtein"
file = "output.txt"
expected = "42"
threshold = 1.0
trigger = "on_stop"
description = "output.txt must contain exactly '42'"
```

Verifiers run in order, stop on first failure. Use `output_schema` instead of json verifiers when the agent produces structured JSON output.

### 5. Smart Verifier Types

**Prefer typed verifiers.** They run in the portlang runtime — no packages required, no container dependencies. Fall back to shell verifiers only for logic that can't be expressed with a typed verifier, and only use tools guaranteed in the container baseline (see section 8).

**Trigger modes:** `on_stop` (default) runs after the agent finishes. `always` runs after every step. `on_tool:<tool_name>` runs after each call to a specific tool — useful for incremental checks, e.g. `trigger = "on_tool:write"` to validate files as they're written.

```toml
# Fuzzy text match (tolerates minor differences)
[[verifier]]
type = "levenshtein"
name = "close-enough"
file = "output.txt"
expected = "The answer is 42."
threshold = 0.9
trigger = "on_stop"
description = "Output must be at least 90% similar to expected"

# Semantic match (meaning, not exact text)
[[verifier]]
type = "semantic"
name = "right-idea"
file = "summary.txt"
expected = "The model achieved high accuracy on the test set."
threshold = 0.85
trigger = "on_stop"
description = "Summary must convey the correct conclusion"
```

Local embedding model downloaded automatically (~67 MB, no API key required).

### 6. Scoped Boundaries

```toml
[boundary]
allow_write = ["output.json", "logs/*.txt"]
network = "deny"
max_tokens = 100000
max_cost = "$1.00"
max_steps = 20
```

### 7. Re-observation (keep context fresh)

```toml
[prompt]
goal = "..."
re_observation = [
  "echo '=== workspace ===' && ls -1 *.py *.txt 2>/dev/null | cat",
  "echo '=== tests ===' && python -m pytest --tb=no -q 2>&1 | tail -5",
]
```

Commands run before each agent step, injecting fresh state into context.

### 8. Custom Environment

```toml
[environment]
root = "./workspace"
packages = ["nodejs", "npm"]    # Install apt packages

# Or use a custom Dockerfile:
dockerfile = "./Dockerfile"

# Or a pre-built image:
image = "myregistry/myimage:latest"
```

**Default container baseline:** The container is minimal. Available by default: standard POSIX shell builtins, `bash`, `curl`, `wc`, `grep`, `cat`, `ls`, `find`. **Not available** unless added to `packages` or a custom image: `python3`, `node`, `jq`, `git`, and most other tools.

Shell verifiers run inside the container and are subject to the same constraints. **Prefer typed verifiers** (`type = "json"`, `"levenshtein"`, `"semantic"`) over shell verifiers whenever possible — they run natively in the portlang runtime and require nothing installed. Only use shell verifiers for checks that require container-side execution, and only invoke tools you've declared in `packages`.

### 9. Custom Tools

**Default tools (always available, no `[[tool]]` entry needed):**
- `bash` — run shell commands in the container
- `glob` — find files by pattern
- `write` — write files to allowed paths

Define `[[tool]]` entries only to add capabilities beyond these three.

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
# /// script
# dependencies = [requests]
# ///
# uv auto-installs dependencies — no packages needed in task.field

def execute(expression: str) -> dict:
    """Evaluate a math expression and return the result."""
    return {"result": eval(expression)}
```

```toml
[[tool]]
type = "python"
file = "./tools/calculator.py"   # relative to the field file, not workspace
function = "execute"  # schema auto-extracted from type hints; omit to expose all functions
```

> **Python tool rules:**
> - Each tool file runs in isolation — tool files cannot import each other. Put all related logic in one file.
> - Declare third-party dependencies with a `# /// script` PEP 723 block at the top; `uv` installs them automatically.
> - File paths in `file =` are relative to the field file, not the workspace root.

**Tool-first design for complex tasks:** For tasks involving multi-step API calls, data aggregation, or web scraping, write Python tools that encapsulate that logic before writing the field. The agent's `goal` should then be: call the tool, write the output file. This keeps steps under 5, cost under $0.05, and `allow_write` naturally minimal. Agents that try to do complex work through raw shell commands (curl pipes, temp files, bash scripts) burn budget and fail more often.

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

### 10. Claude Code Runner

Use `--runner claude-code` to run the agent loop through Claude Code instead of the native runner. This gives the agent Edit, Glob, Grep, LSP, WebSearch, and WebFetch — the full Claude Code toolset — inside portlang's sandbox and verifier system.

```bash
portlang run example.field --runner claude-code
```

**Auth:** if Claude Code is already installed and authenticated, no setup is needed — portlang reads credentials from `~/.claude/.credentials.json` automatically. Otherwise run `claude setup-token`, or set `ANTHROPIC_API_KEY`.

**How field config maps to Claude Code:**

| Field config | Behavior |
|---|---|
| `model.name` | Passed to Claude Code |
| `[[tool]]` MCP | Passed directly via `--mcp-config` |
| `[[tool]]` shell/python | Wrapped as MCP stdio servers, run in container |
| `boundary.allow_write` | Enforced via PostToolUse hook on Write/Edit |
| `boundary.max_steps/cost/tokens` | Monitored from stream; process killed on breach |
| `[[verifier]]` shell, `on_stop` | Run by portlang after agent exits |
| `[[verifier]]` shell, `always`/`on_tool` | Run as Claude Code PostToolUse hooks |
| `boundary.network` | Always enabled (Claude Code requires API access) |

**Limitations vs native runner:** `tool_call` verifiers and boundary context tracing are not supported.

### 11. Batch Evaluation

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
- Start conservative: `max_cost = "$0.25"` for simple tasks, `$1.00` for network-heavy tasks; increase after profiling
- Increase `max_tokens` or reduce `max_steps` in `[boundary]`
- Simplify `re_observation` commands
- Check for tool error loops
- Move complex logic into Python tools so the agent does orchestration, not implementation

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
- **reference/field_recipes.md** - 8 complete field examples

## Core Principles

1. **Boundaries are topology, not policy** - Make bad actions impossible, not discouraged
2. **Verifiers are runtime reward signals** - Not post-hoc checks, they steer behavior
3. **Context is finite** - Hard ceiling, no magic compression
4. **Trajectories are data** - Replay, diff, analyze distributions
5. **Engineer the space, not the searcher** - Agent policy is opaque, environment is yours

---

*GitHub: https://github.com/portofcontext/portlang*
