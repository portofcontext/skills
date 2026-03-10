# Custom Tools Guide

portlang supports three types of custom tools: Shell, Python, and MCP servers. This guide shows you how to create and integrate each type.

## Overview

**Why custom tools?**
- Extend agent capabilities beyond built-in Read/Write/Glob
- Encapsulate complex operations (API calls, data processing)
- Reuse logic across multiple fields
- Provide domain-specific functionality

**When to use each type:**
- **Shell:** Simple file operations, system commands, CLI wrappers
- **Python:** Data processing, complex logic, external libraries
- **MCP:** Third-party integrations, databases, APIs

## Shell Tools

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

For more complex logic, point the command at a script:

**tools/word_count.sh:**
```bash
#!/bin/bash
set -e
FILE="$1"
if [ ! -f "$FILE" ]; then
    echo "{\"error\": \"File not found: $FILE\"}"
    exit 1
fi
COUNT=$(wc -w "$FILE" | awk '{print $1}')
echo "{\"count\": $COUNT}"
```

```toml
[[tool]]
type = "shell"
name = "word_count"
description = "Count words in a file and return JSON"
command = "./tools/word_count.sh {file}"
input_schema = '{"type": "object", "properties": {"file": {"type": "string"}}, "required": ["file"]}'
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

### Complex Example: HTTP Request Tool

```toml
[[tool]]
type = "shell"
name = "http_get"
description = "Fetch a URL and return the response body"
command = "curl -s {url}"
input_schema = '{"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}'
```

For richer output (status code + body), use a script:

```bash
#!/bin/bash
# tools/http_get.sh
URL="$1"
RESPONSE=$(curl -s -w "\n%{http_code}" "$URL")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)
ESCAPED_BODY=$(echo "$BODY" | jq -Rs .)
echo "{\"status\": $STATUS, \"body\": $ESCAPED_BODY}"
```

```toml
[[tool]]
type = "shell"
name = "http_get"
description = "Fetch URL, returns status and body"
command = "./tools/http_get.sh {url}"
input_schema = '{"type": "object", "properties": {"url": {"type": "string"}}, "required": ["url"]}'
```

## Python Tools

### Basic Structure

Python tools are functions with typed parameters. portlang auto-extracts the JSON schema from type hints; no manual schema definition needed.

**Definition in field.toml:**
```toml
[[tool]]
type = "python"
file = "./tools/analyzer.py"
function = "analyze_text"  # omit to expose all functions
```

**tools/analyzer.py:**
```python
#!/usr/bin/env python3
# /// script
# dependencies = []
# ///

def analyze_text(text: str) -> dict:
    """Analyze text and return word count, character count, and average word length."""
    if not text:
        return {"error": "Text cannot be empty"}
    words = text.split()
    word_count = len(words)
    avg_word_length = sum(len(w) for w in words) / word_count if word_count > 0 else 0
    return {
        "word_count": word_count,
        "char_count": len(text),
        "avg_word_length": round(avg_word_length, 2)
    }
```

### PEP 723 Inline Dependencies

For tools requiring external libraries, use PEP 723 format:

```python
#!/usr/bin/env python3
# /// script
# dependencies = [
#   "pandas>=2.0.0",
#   "numpy>=1.24.0",
# ]
# ///

def compute_stats(operation: str, data: list) -> dict:
    """Compute mean or median of a list of numbers."""
    import numpy as np
    if operation == "mean":
        return {"result": float(np.mean(data))}
    elif operation == "median":
        return {"result": float(np.median(data))}
    else:
        return {"error": f"Unknown operation: {operation}"}
```

**Runtime behavior:**
- portlang parses dependencies from comments
- Creates isolated virtual environment
- Installs dependencies automatically
- Caches environment for reuse

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

Use typed parameters — portlang validates inputs before calling the function. Handle exceptions and always return a dict:

```python
#!/usr/bin/env python3

def process_file(path: str, mode: str) -> dict:
    """Process a file in the given mode ('count' or 'summarize')."""
    try:
        if mode not in ("count", "summarize"):
            return {"error": f"Unknown mode: {mode}", "success": False}
        with open(path) as f:
            content = f.read()
        if mode == "count":
            return {"success": True, "result": len(content.split())}
        return {"success": True, "result": content[:200]}
    except FileNotFoundError as e:
        return {"error": f"File not found: {e.filename}", "success": False}
    except Exception as e:
        return {"error": f"Unexpected error: {str(e)}", "success": False}
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

| Use Case | Recommended Type | Why |
|----------|-----------------|-----|
| File operations | Shell | Simple, fast, no dependencies |
| Data processing | Python | Rich ecosystem, pandas/numpy |
| API calls | Shell (curl) or Python (requests) | Both work, Python has better error handling |
| Database queries | MCP | Use official MCP database servers |
| Complex logic | Python | Type hints, testing, libraries |
| System commands | Shell | Direct access to CLI tools |
| Third-party integrations | MCP | Standard protocol, many servers available |

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
