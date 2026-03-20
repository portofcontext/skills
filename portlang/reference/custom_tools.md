# Custom Tools Guide

portlang supports three types of custom tools: Shell, Python, and MCP servers. This guide shows you how to create and integrate each type.

## Overview

**Why custom tools?**
- Extend agent capabilities beyond built-in Read/Write/Glob
- Encapsulate complex operations (API calls, data processing)
- Reuse logic across multiple fields
- Provide domain-specific functionality

**When to use each type:**
- **Python:** Default choice. API calls, data processing, file parsing, any logic that can fail. Auto-schema from type hints, PEP 723 dependency management, structured dict returns.
- **Shell:** Trivial single-command wrappers only (`wc`, `cp`, `ls`). Do not use for anything that parses output or chains commands.
- **MCP:** Third-party integrations, databases, APIs with official MCP servers.

## Python Tools

Python tools are the **default choice** for custom tools in portlang. They give you typed parameters, Pydantic return types, automatic dependency management via PEP 723, and structured output — no manual JSON schema, no shell escaping, no fragile pipelines.

### How auto-extraction works

portlang extracts everything the agent needs to use a tool directly from the Python function. **The quality of these annotations determines how well the agent uses the tool.**

| Python source | What the agent sees |
|---|---|
| Function name (`fetch_data`) | Tool name |
| Docstring | Tool description — how the agent decides when to call it |
| Parameter names + type hints | Input schema (validated before the function is called) |
| `Literal["a", "b"]` types | Enum constraints in the schema |
| Pydantic `BaseModel` return type | Output schema — the agent knows exactly what it will get back |

This means:
- A vague docstring → agent misuses the tool
- `str` where you mean `Literal["csv", "json"]` → agent passes invalid values
- `-> dict` return → agent gets no output schema, can't reason about the result
- `-> MyModel(BaseModel)` return → agent sees typed fields with descriptions

**Write functions as if the docstring and type hints are the only documentation the agent will ever see — because they are.**

### Basic Structure

**Definition in field.toml:**
```toml
[[tool]]
type = "python"
file = "./tools/analyzer.py"
function = "analyze_text"  # schema auto-extracted from type hints; omit to expose all functions
```

**tools/analyzer.py:**
```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pydantic"]
# ///

from pydantic import BaseModel

class TextStats(BaseModel):
    word_count: int
    char_count: int
    avg_word_length: float

def analyze_text(text: str) -> TextStats:
    """Analyze text and return word count, character count, and average word length."""
    if not text:
        raise ValueError("Text cannot be empty")
    words = text.split()
    word_count = len(words)
    avg_word_length = sum(len(w) for w in words) / word_count if word_count > 0 else 0
    return TextStats(
        word_count=word_count,
        char_count=len(text),
        avg_word_length=round(avg_word_length, 2),
    )
```

### PEP 723 Inline Dependencies

Declare third-party dependencies at the top of the file. `uv` installs them automatically — no need to add packages to `[environment]`. Use Pydantic for return types so portlang auto-extracts the JSON schema.

```python
#!/usr/bin/env python3
# /// script
# dependencies = [
#   "numpy>=1.24.0",
#   "pydantic",
# ]
# ///

from pydantic import BaseModel
from typing import Literal
import numpy as np

class StatsResult(BaseModel):
    operation: Literal["mean", "median"]
    result: float

def compute_stats(operation: Literal["mean", "median"], data: list[float]) -> StatsResult:
    """Compute mean or median of a list of numbers."""
    value = float(np.mean(data)) if operation == "mean" else float(np.median(data))
    return StatsResult(operation=operation, result=value)
```

**Runtime behavior:**
- portlang parses dependencies from comments
- Creates isolated virtual environment
- Installs dependencies automatically
- Caches environment for reuse

### HTTP API Example

Use `requests` instead of shell `curl` — typed, error-handled, no escaping:

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["requests", "pydantic"]
# ///

import json, pathlib
import requests
from pydantic import BaseModel

class FetchResult(BaseModel):
    status: int
    output_path: str
    record_count: int

def http_get(url: str, output_path: str) -> FetchResult:
    """Fetch JSON from a URL and write it to output_path."""
    resp = requests.get(url, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    pathlib.Path(output_path).write_text(json.dumps(data, indent=2))
    count = len(data) if isinstance(data, list) else 1
    return FetchResult(status=resp.status_code, output_path=output_path, record_count=count)
```

```toml
[[tool]]
type = "python"
file = "./tools/http_get.py"
function = "http_get"
```

### File Processing Example

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pandas"]
# ///

def filter_csv(file: str, filter_column: str, filter_value: str, output: str) -> dict:
    """Filter a CSV file by column value and save to output path."""
    import pandas as pd
    try:
        df = pd.read_csv(file)
        if filter_column not in df.columns:
            return {"error": f"Column {filter_column} not found"}
        filtered = df[df[filter_column] == filter_value]
        filtered.to_csv(output, index=False)
        return {"rows_filtered": len(filtered), "output_file": output}
    except Exception as e:
        return {"error": str(e)}
```

### JSON Schema Validator Example

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["jsonschema"]
# ///

def validate_schema(data: dict, schema: dict) -> dict:
    """Validate a JSON object against a JSON schema."""
    from jsonschema import validate, ValidationError
    try:
        validate(instance=data, schema=schema)
        return {"valid": True, "errors": []}
    except ValidationError as e:
        return {"valid": False, "errors": [str(e)]}
```

### Error Handling Best Practices

Use Pydantic models for return types — portlang extracts the schema automatically. Raise exceptions on errors rather than returning error dicts:

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pydantic"]
# ///

from pydantic import BaseModel
from typing import Literal

class FileResult(BaseModel):
    mode: Literal["count", "summarize"]
    result: str | int

def process_file(path: str, mode: Literal["count", "summarize"]) -> FileResult:
    """Process a file in the given mode ('count' or 'summarize')."""
    with open(path) as f:
        content = f.read()
    if mode == "count":
        return FileResult(mode=mode, result=len(content.split()))
    return FileResult(mode=mode, result=content[:200])
```

## Shell Tools

Shell tools are for **trivial single-command wrappers only**. If you need to parse output, chain commands, or handle errors — use a Python tool instead.

### Basic Structure

Shell tools use a **command template** where `{param}` placeholders are substituted with agent-provided values. Output goes to stdout.

**Definition in field.toml:**
```toml
[[tool]]
type = "shell"
name = "word_count"
description = "Count words in a file"
command = "wc -w {file}"
input_schema = '{"type": "object", "properties": {"file": {"type": "string"}}, "required": ["file"]}'
```

**Agent usage:**
```
Agent calls: word_count({"file": "data.txt"})
Runtime executes: wc -w data.txt
Output: 1234 data.txt
```

### Multi-Parameter Tools

```toml
[[tool]]
type = "shell"
name = "file_copy"
description = "Copy a file to a new location"
command = "cp {source} {destination} && echo '{\"success\": true}'"
input_schema = '{"type": "object", "properties": {"source": {"type": "string"}, "destination": {"type": "string"}}, "required": ["source", "destination"]}'
```

## MCP Servers

### What is MCP?

MCP (Model Context Protocol) is Anthropic's standard protocol for connecting LLMs to data sources. MCP servers expose tools, resources, and prompts via a standard interface.

**Transport types:**
- **stdio:** Server runs as subprocess, communicates via stdin/stdout
- **HTTP:** Server runs as HTTP service
- **SSE (Server-Sent Events):** Server runs as SSE service

### Finding MCP Servers

**Official registry:**
- https://github.com/modelcontextprotocol/servers

**npm registry:**
```bash
npm search mcp-server
```

**Popular servers:**
- `@modelcontextprotocol/server-filesystem` - File operations
- `@modelcontextprotocol/server-github` - GitHub API
- `@modelcontextprotocol/server-postgres` - PostgreSQL database
- `@modelcontextprotocol/server-sqlite` - SQLite database
- `@modelcontextprotocol/server-brave-search` - Web search

### Stdio MCP Configuration

**Example: Filesystem server**

```toml
[[tool]]
type = "mcp"
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
transport = "stdio"
```

**How it works:**
1. Runtime spawns: `npx -y @modelcontextprotocol/server-filesystem /workspace`
2. Server outputs available tools via stdout
3. Agent can call tools like `read_file`, `write_file`, `list_directory`
4. Runtime forwards requests/responses via JSON-RPC over stdio

**Example: GitHub server**

```toml
[[tool]]
type = "mcp"
name = "github"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-github"]
env = { GITHUB_TOKEN = "${GITHUB_TOKEN}" }
transport = "stdio"
```

**Environment variables:**
- Use `env` field to pass secrets
- Use `${VAR}` syntax to reference environment variables
- Variables are substituted at runtime from host environment

### HTTP MCP Configuration

**Example: Remote MCP server**

```toml
[[tool]]
type = "mcp"
name = "analytics"
url = "https://api.example.com/mcp"
transport = "http"
headers = { "Authorization" = "Bearer ${API_KEY}" }
```

**How it works:**
1. Runtime sends HTTP POST to `https://api.example.com/mcp`
2. Request body: JSON-RPC formatted tool call
3. Response: JSON-RPC formatted result

### Debugging MCP Connections

**Test stdio server manually:**

```bash
# Run server
npx -y @modelcontextprotocol/server-filesystem /workspace

# Server should output JSON describing available tools
```

**Check portlang output:**

```bash
portlang run field.toml
# Look for MCP connection messages in output:
# "MCP server started: filesystem"
# "Available tools: [read_file, write_file, ...]"
```

**Common issues:**

1. **Server not found:**
   - Ensure `npx` can install package: `npx -y @modelcontextprotocol/server-filesystem`
   - Check internet connection

2. **Permission errors:**
   - Check file paths are accessible
   - Verify environment variables are set

3. **Tool not available:**
   - List available tools: Run server manually and check output
   - Tool name might be different than expected

### Custom MCP Server

You can create your own MCP server:

**Simple Python MCP server (stdio):**

```python
#!/usr/bin/env python3
import json
import sys

def handle_request(request):
    """Handle JSON-RPC request."""
    method = request.get("method")

    if method == "tools/list":
        return {
            "tools": [
                {
                    "name": "calculate",
                    "description": "Perform arithmetic",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "operation": {"type": "string", "enum": ["add", "subtract"]},
                            "a": {"type": "number"},
                            "b": {"type": "number"}
                        },
                        "required": ["operation", "a", "b"]
                    }
                }
            ]
        }

    elif method == "tools/call":
        tool_name = request["params"]["name"]
        args = request["params"]["arguments"]

        if tool_name == "calculate":
            op = args["operation"]
            a, b = args["a"], args["b"]
            if op == "add":
                result = a + b
            elif op == "subtract":
                result = a - b
            return {"content": [{"type": "text", "text": str(result)}]}

    return {"error": "Unknown method"}

def main():
    """MCP server main loop."""
    for line in sys.stdin:
        request = json.loads(line)
        response = handle_request(request)
        print(json.dumps(response), flush=True)

if __name__ == "__main__":
    main()
```

**Use in field.toml:**

```toml
[[tool]]
type = "mcp"
name = "calculator"
command = "python"
args = ["./tools/mcp_calculator.py"]
transport = "stdio"
```

## Tool Selection Guide

**Default to Python.** Shell tools are for trivial single-command wrappers only. If you're writing more than one shell command, or parsing output, or calling an API — use a Python tool instead.

| Use Case | Recommended Type | Why |
|----------|-----------------|-----|
| API calls / HTTP | **Python** (requests) | Typed params, error handling, JSON parsing |
| Data processing | **Python** (pandas/numpy) | Rich ecosystem, structured returns |
| File parsing / transformation | **Python** | Error handling, libraries, no shell escaping |
| Complex logic | **Python** | Type hints, auto-schema, testable |
| Database queries | **MCP** | Use official MCP database servers |
| Third-party integrations | **MCP** | Standard protocol, many servers available |
| Trivial single commands | Shell | Only for `wc`, `cp`, `ls`, etc. — nothing that parses output |

### Python vs Shell: When to choose

Use **Python** when the tool needs to:
- Parse or validate output (JSON, CSV, regex)
- Call an HTTP API
- Handle errors gracefully with structured responses
- Use any external library
- Do anything that would require piping shell commands together

Use **Shell** only when the tool is a thin wrapper around one standard command and failures are acceptable to surface as raw exit codes.

## Testing Custom Tools

### Test Shell Tools

```bash
# Run directly
./tools/word_count.sh test.txt

# Expected output (JSON):
# {"count": 123}

# Test error handling
./tools/word_count.sh nonexistent.txt
# {"error": "File not found: nonexistent.txt"}
```

### Test Python Tools

```bash
# Run with test input
python -c "
from tools.analyzer import analyze_text
result = analyze_text('hello world')
print(result)
"

# Expected: {'word_count': 2, 'char_count': 11, 'avg_word_length': 5.0}
```

### Test MCP Servers

```bash
# Test stdio server
echo '{"method": "tools/list"}' | npx -y @modelcontextprotocol/server-filesystem /workspace

# Should output JSON listing available tools
```

## Best Practices

1. **Always validate inputs:** Check for required parameters and types
2. **Return valid JSON:** Even on errors, return structured error objects
3. **Handle errors gracefully:** Catch exceptions, return meaningful messages
4. **Document tool behavior:** Include description comments in scripts
5. **Test independently:** Tools should work standalone, not just in portlang
6. **Keep tools focused:** One tool = one responsibility
7. **Use appropriate types:** Shell for simple, Python for complex, MCP for integrations
8. **Version dependencies:** Pin versions in PEP 723 comments
9. **Secure secrets:** Use environment variables, never hardcode
10. **Make scripts executable:** `chmod +x tools/*.sh`
