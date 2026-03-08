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

Shell tools receive parameters as command-line arguments and output JSON to stdout.

**Definition in field.toml:**
```toml
[[tool]]
type = "shell"
script = "./tools/word_count.sh"
```

**Script format (tools/word_count.sh):**
```bash
#!/bin/bash
# Tool: word_count
# Description: Count words in a file
# Input: file (string)
# Output: {"count": number}

set -e  # Exit on error

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "{\"error\": \"File not found: $FILE\"}"
    exit 1
fi

COUNT=$(wc -w "$FILE" | awk '{print $1}')
echo "{\"count\": $COUNT}"
```

**Make executable:**
```bash
chmod +x tools/word_count.sh
```

**Agent usage:**
```
Agent calls: word_count({"file": "data.txt"})
Runtime executes: ./tools/word_count.sh data.txt
Output: {"count": 1234}
```

### Parameter Handling

Multiple parameters are passed as separate arguments:

**Script:**
```bash
#!/bin/bash
# Tool: file_copy
# Input: source (string), destination (string)
# Output: {"success": boolean}

SOURCE="$1"
DEST="$2"

if [ ! -f "$SOURCE" ]; then
    echo "{\"error\": \"Source file not found\", \"success\": false}"
    exit 1
fi

cp "$SOURCE" "$DEST"
echo "{\"success\": true, \"destination\": \"$DEST\"}"
```

### Error Handling

Always handle errors and return valid JSON:

```bash
#!/bin/bash
# Tool: grep_wrapper
# Input: pattern (string), file (string)
# Output: {"matches": array, "count": number}

PATTERN="$1"
FILE="$2"

# Validate inputs
if [ -z "$PATTERN" ]; then
    echo "{\"error\": \"Pattern cannot be empty\", \"matches\": [], \"count\": 0}"
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "{\"error\": \"File not found\", \"matches\": [], \"count\": 0}"
    exit 1
fi

# Perform grep (|| true to not fail if no matches)
MATCHES=$(grep "$PATTERN" "$FILE" || true)

if [ -z "$MATCHES" ]; then
    echo "{\"matches\": [], \"count\": 0}"
else
    # Convert matches to JSON array
    JSON_MATCHES=$(echo "$MATCHES" | jq -R . | jq -s .)
    COUNT=$(echo "$MATCHES" | wc -l | tr -d ' ')
    echo "{\"matches\": $JSON_MATCHES, \"count\": $COUNT}"
fi
```

### Complex Example: HTTP Request Tool

```bash
#!/bin/bash
# Tool: http_get
# Input: url (string), headers (object, optional)
# Output: {"status": number, "body": string}

URL="$1"
HEADERS="${2:-{}}"  # Default to empty object if not provided

# Basic validation
if [ -z "$URL" ]; then
    echo "{\"error\": \"URL required\", \"status\": 0, \"body\": \"\"}"
    exit 1
fi

# Make request (using curl)
RESPONSE=$(curl -s -w "\n%{http_code}" "$URL")
BODY=$(echo "$RESPONSE" | head -n -1)
STATUS=$(echo "$RESPONSE" | tail -n 1)

# Escape body for JSON
ESCAPED_BODY=$(echo "$BODY" | jq -Rs .)

echo "{\"status\": $STATUS, \"body\": $ESCAPED_BODY}"
```

## Python Tools

### Basic Structure

Python tools must have an `execute(input: dict) -> dict` function.

**Definition in field.toml:**
```toml
[[tool]]
type = "python"
script = "./tools/analyzer.py"
```

**Script format (tools/analyzer.py):**
```python
#!/usr/bin/env python3
# /// script
# dependencies = []
# ///

def execute(input: dict) -> dict:
    """
    Analyze text and return statistics.

    Input: {"text": "string"}
    Output: {"word_count": int, "char_count": int, "avg_word_length": float}
    """
    text = input.get("text", "")

    if not text:
        return {"error": "Text cannot be empty"}

    words = text.split()
    word_count = len(words)
    char_count = len(text)
    avg_word_length = sum(len(w) for w in words) / word_count if word_count > 0 else 0

    return {
        "word_count": word_count,
        "char_count": char_count,
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
#   "requests>=2.31.0",
# ]
# ///

def execute(input: dict) -> dict:
    """Data processor with external dependencies."""
    import pandas as pd
    import numpy as np

    operation = input.get("operation")
    data = input.get("data", [])

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

def execute(input: dict) -> dict:
    """
    Load and filter CSV data.

    Input: {
        "file": "string",
        "filter_column": "string",
        "filter_value": any,
        "output": "string"
    }
    Output: {"rows_filtered": int, "output_file": string}
    """
    import pandas as pd

    try:
        file_path = input.get("file")
        filter_col = input.get("filter_column")
        filter_val = input.get("filter_value")
        output_path = input.get("output")

        # Validate inputs
        if not all([file_path, filter_col, output_path]):
            return {"error": "Missing required parameters"}

        # Load data
        df = pd.read_csv(file_path)

        # Filter
        if filter_col in df.columns:
            filtered_df = df[df[filter_col] == filter_val]
        else:
            return {"error": f"Column {filter_col} not found"}

        # Save
        filtered_df.to_csv(output_path, index=False)

        return {
            "rows_filtered": len(filtered_df),
            "output_file": output_path
        }

    except Exception as e:
        return {"error": str(e)}
```

### JSON Schema Validator Example

```python
#!/usr/bin/env python3
# /// script
# dependencies = ["jsonschema"]
# ///

def execute(input: dict) -> dict:
    """
    Validate JSON against a schema.

    Input: {
        "data": object,
        "schema": object
    }
    Output: {"valid": bool, "errors": array}
    """
    from jsonschema import validate, ValidationError

    data = input.get("data")
    schema = input.get("schema")

    if not data or not schema:
        return {"error": "Both data and schema required"}

    try:
        validate(instance=data, schema=schema)
        return {"valid": True, "errors": []}
    except ValidationError as e:
        return {
            "valid": False,
            "errors": [str(e)]
        }
```

### Error Handling Best Practices

```python
#!/usr/bin/env python3

def execute(input: dict) -> dict:
    """Template with comprehensive error handling."""
    try:
        # Validate required parameters
        required = ["param1", "param2"]
        missing = [p for p in required if p not in input]
        if missing:
            return {
                "error": f"Missing required parameters: {', '.join(missing)}",
                "success": False
            }

        # Validate types
        if not isinstance(input["param1"], str):
            return {"error": "param1 must be a string", "success": False}

        # Validate values
        if input["param2"] < 0:
            return {"error": "param2 must be non-negative", "success": False}

        # Perform operation
        result = do_something(input["param1"], input["param2"])

        return {
            "success": True,
            "result": result
        }

    except FileNotFoundError as e:
        return {"error": f"File not found: {e.filename}", "success": False}
    except PermissionError:
        return {"error": "Permission denied", "success": False}
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

**Check portlang logs:**

```bash
# Run with verbose logging
portlang run field.toml --verbose

# Look for MCP connection messages:
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
from tools.analyzer import execute
result = execute({'text': 'hello world'})
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
