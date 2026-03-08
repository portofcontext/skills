# Field Recipes

Complete, working field.toml examples for common use cases. Copy, modify, and use as templates for your own fields.

## Recipe 1: Hello World (Minimal)

**Use case:** Simplest possible field, creates a single file.

```toml
name = "hello-world"
description = "Create a simple hello world program"

goal = """
Create a Python file called hello.py that prints "Hello, World!" when run.
Stop once the file is created.
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
max_steps = 5

[[verifiers]]
name = "file-exists"
command = "test -f hello.py"
trigger = "on_stop"
description = "hello.py must exist"

[[verifiers]]
name = "runs-successfully"
command = "python hello.py 2>&1 | grep -q 'Hello, World!'"
trigger = "on_stop"
description = "Running hello.py must print 'Hello, World!'"
```

**Expected behavior:**
- Agent creates `hello.py`
- Agent stops
- Verifiers check file exists and runs correctly
- Typical tokens: ~2k, cost: ~$0.06

---

## Recipe 2: Code Generation with Tests

**Use case:** Generate Python code with comprehensive test suite.

```toml
name = "code-task"
description = "Generate code with tests and verify they pass"

goal = """
Create a Python program that analyzes text files and reports statistics.

Your program should:
1. Read a text file and count total words, unique words, average word length, and top 5 most common words
2. Save the analysis to a JSON file
3. Accept arguments: python analyzer.py input.txt output.json
4. Include pytest tests in test_analyzer.py that verify all functionality
5. Include a requirements.txt listing pytest

Create exactly three files: analyzer.py, test_analyzer.py, requirements.txt.
Once all three exist, stop — the verifier will run the tests automatically.
"""

re_observation = [
    "echo '=== workspace ===' && ls -1 *.py *.txt 2>/dev/null | cat"
]

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["*.py", "*.txt", "requirements.txt"]

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 30

[[verifiers]]
name = "files-exist"
command = "test -f analyzer.py && test -f test_analyzer.py && test -f requirements.txt"
trigger = "on_stop"
description = "All three files must exist"

[[verifiers]]
name = "pytest"
command = "python -m pytest test_analyzer.py -v 2>&1"
trigger = "on_stop"
description = "All tests must pass"
```

**Design choices:**
- `re_observation` shows files after each step (keeps agent aware of state)
- `allow_write` uses glob patterns for flexibility
- Two-layer verification: existence then correctness
- Typical tokens: ~15k, cost: ~$0.45

---

## Recipe 3: Data Pipeline with Code Mode

**Use case:** Process large CSV files efficiently without loading into context.

```toml
name = "data-filtering"
description = "Filter and transform data using Code Mode"

goal = """
You have access to data tools and user data in the workspace.

Task:
1. Load users.json (contains 100 user records)
2. Filter to only users with age > 30
3. Sort the results alphabetically by name
4. Write the filtered and sorted list to output.json

With Code Mode enabled, you can process this efficiently
without passing all data through your context window.

Stop once output.json is created correctly.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 0.0
max_tokens = 8000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["output.json"]
network = "deny"

[context]
max_tokens = 100000
max_cost = "$1.00"
max_steps = 15

# Enable Code Mode for token efficiency
[code_mode]
enabled = true

# Python tools exposed in Code Mode
[[tool]]
type = "python"
script = "./tools/data_tools.py"

[[verifiers]]
name = "correct-filter"
command = """
python3 -c "
import json
with open('output.json') as f:
    users = json.load(f)
# Check count
assert len(users) == 58, f'Expected 58 users, got {len(users)}'
# Check all ages > 30
assert all(u['age'] > 30 for u in users), 'Not all users have age > 30'
# Check sorted by name
names = [u['name'] for u in users]
assert names == sorted(names), 'Users not sorted by name'
print('✓ Correct filtering and sorting')
"
"""
trigger = "on_stop"
description = "Output contains correctly filtered and sorted users"
```

**data_tools.py:**
```python
#!/usr/bin/env python3
# /// script
# dependencies = ["pandas"]
# ///

def execute(input: dict) -> dict:
    import pandas as pd
    operation = input.get("operation")

    if operation == "filter_and_sort":
        df = pd.read_json("users.json")
        filtered = df[df["age"] > input["min_age"]]
        sorted_df = filtered.sort_values("name")
        sorted_df.to_json("output.json", orient="records")
        return {"count": len(sorted_df)}

    return {"error": "Unknown operation"}
```

**Design choices:**
- Temperature 0.0 for deterministic data processing
- Code Mode reduces token usage from ~100k to ~5k
- `network = "deny"` prevents external API calls
- Comprehensive verifier checks count, filter, and sort

---

## Recipe 4: API Integration

**Use case:** Make HTTP requests and process responses.

```toml
name = "api-integration"
description = "Fetch data from API and transform it"

goal = """
Fetch user data from the JSONPlaceholder API and create a summary.

Task:
1. Use the http_get tool to fetch from: https://jsonplaceholder.typicode.com/users
2. Extract just the names and email addresses
3. Save to summary.json as a list of objects with 'name' and 'email' fields
4. Sort by name alphabetically

Stop once summary.json is created.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["summary.json"]
network = "allow"  # Required for HTTP requests

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 10

[[tool]]
type = "shell"
script = "./tools/http_get.sh"

[[verifiers]]
name = "output-exists"
command = "test -f summary.json"
trigger = "on_stop"
description = "summary.json must exist"

[[verifiers]]
name = "valid-json"
command = "python -m json.tool summary.json > /dev/null"
trigger = "on_stop"
description = "summary.json must be valid JSON"

[[verifiers]]
name = "schema-correct"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
assert isinstance(data, list), 'Data must be a list'
assert len(data) == 10, f'Expected 10 users, got {len(data)}'
for item in data:
    assert 'name' in item and 'email' in item, 'Each item must have name and email'
# Check sorted
names = [item['name'] for item in data]
assert names == sorted(names), 'Must be sorted by name'
print('✓ Schema and sorting correct')
"
"""
trigger = "on_stop"
description = "Data must be list of 10 objects with name/email, sorted by name"
```

**tools/http_get.sh:**
```bash
#!/bin/bash
URL="$1"
curl -s "$URL"
```

**Design choices:**
- `network = "allow"` explicitly enables network access
- Three-layer verification: exists → valid JSON → correct schema
- Custom HTTP tool wraps curl for simplicity

---

## Recipe 5: Multi-Layer Verification Pattern

**Use case:** Progressive validation from simple to complex.

```toml
name = "sales-analysis"
description = "Process sales data with strict validation"

goal = """
Read sales.csv and calculate total revenue per region.

Output a JSON file (summary.json) with this structure:
{
  "North": <total_revenue>,
  "South": <total_revenue>,
  "East": <total_revenue>,
  "West": <total_revenue>
}

Stop once summary.json is created.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["summary.json"]
allow_read = ["sales.csv"]
network = "deny"

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 20

# Layer 1: File exists
[[verifiers]]
name = "output-exists"
command = "test -f summary.json"
trigger = "on_stop"
description = "summary.json must exist"

# Layer 2: Valid JSON syntax
[[verifiers]]
name = "valid-json"
command = "python -m json.tool summary.json > /dev/null"
trigger = "on_stop"
description = "summary.json must be valid JSON"

# Layer 3: Required fields present
[[verifiers]]
name = "schema-valid"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
required = ['North', 'South', 'East', 'West']
assert all(k in data for k in required), f'Missing regions. Required: {required}, Found: {list(data.keys())}'
print('✓ All regions present')
"
"""
trigger = "on_stop"
description = "JSON must have all four regions: North, South, East, West"

# Layer 4: Value types correct
[[verifiers]]
name = "value-types"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
for region, revenue in data.items():
    assert isinstance(revenue, (int, float)), f'{region} revenue must be numeric, got {type(revenue)}'
print('✓ All revenues are numeric')
"
"""
trigger = "on_stop"
description = "All revenue values must be numeric (int or float)"

# Layer 5: Data integrity
[[verifiers]]
name = "data-integrity"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
# All revenues must be positive
for region, revenue in data.items():
    assert revenue > 0, f'{region} revenue must be positive, got {revenue}'
# Total should be reasonable (sanity check)
total = sum(data.values())
assert total > 1000, f'Total revenue {total} seems too low'
print(f'✓ Data integrity verified. Total: {total}')
"
"""
trigger = "on_stop"
description = "All revenues must be positive and total must be > 1000"
```

**Design choices:**
- Five verification layers catch errors at appropriate level
- Early failures give precise feedback (e.g., "Missing region: North")
- `allow_read` restricts to input file only
- Each verifier builds on previous (only runs if prior passes)

---

## Recipe 6: Custom Python Tools

**Use case:** Complex data analysis with custom tools.

```toml
name = "text-analysis"
description = "Analyze text using custom Python tools"

goal = """
Analyze the file article.txt using the available analysis tools.

Generate a report (report.json) containing:
- word_count
- sentiment (positive/negative/neutral)
- readability_score
- top_keywords (list of 5)

Stop once report.json is created.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["report.json"]
allow_read = ["article.txt"]

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 15

[[tool]]
type = "python"
script = "./tools/text_analyzer.py"

[[verifiers]]
name = "report-valid"
command = """
python -c "
import json
with open('report.json') as f:
    report = json.load(f)
# Check required fields
required = ['word_count', 'sentiment', 'readability_score', 'top_keywords']
assert all(k in report for k in required), f'Missing fields: {[k for k in required if k not in report]}'
# Check types
assert isinstance(report['word_count'], int), 'word_count must be int'
assert report['sentiment'] in ['positive', 'negative', 'neutral'], 'Invalid sentiment'
assert isinstance(report['readability_score'], (int, float)), 'readability_score must be numeric'
assert isinstance(report['top_keywords'], list) and len(report['top_keywords']) == 5, 'top_keywords must be list of 5'
print('✓ Report valid')
"
"""
trigger = "on_stop"
description = "Report must have all required fields with correct types"
```

**tools/text_analyzer.py:**
```python
#!/usr/bin/env python3
# /// script
# dependencies = ["textstat"]
# ///

def execute(input: dict) -> dict:
    import textstat
    from collections import Counter
    import re

    operation = input.get("operation")
    text = input.get("text", "")

    if operation == "analyze":
        words = re.findall(r'\w+', text.lower())
        word_count = len(words)

        # Simple sentiment
        positive_words = ["good", "great", "excellent", "happy"]
        negative_words = ["bad", "terrible", "sad", "awful"]
        pos_count = sum(1 for w in words if w in positive_words)
        neg_count = sum(1 for w in words if w in negative_words)
        sentiment = "positive" if pos_count > neg_count else "negative" if neg_count > pos_count else "neutral"

        # Readability
        readability = textstat.flesch_reading_ease(text)

        # Keywords
        word_freq = Counter(words)
        top_keywords = [word for word, _ in word_freq.most_common(5)]

        return {
            "word_count": word_count,
            "sentiment": sentiment,
            "readability_score": readability,
            "top_keywords": top_keywords
        }

    return {"error": "Unknown operation"}
```

**Design choices:**
- Custom tool encapsulates complex analysis logic
- PEP 723 dependencies (textstat) installed automatically
- Single comprehensive verifier checks all fields

---

## Recipe 7: MCP Server Integration

**Use case:** Use MCP filesystem server for file operations.

```toml
name = "mcp-file-ops"
description = "File operations using MCP server"

goal = """
Using the filesystem MCP server, perform these operations:

1. List all .txt files in the workspace
2. Read the contents of each .txt file
3. Create a summary.json with:
   - filename
   - line_count
   - word_count

Stop once summary.json is created.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["summary.json"]

[context]
max_tokens = 80000
max_cost = "$1.00"
max_steps = 20

[[tool]]
type = "mcp"
name = "filesystem"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
transport = "stdio"

[[verifiers]]
name = "summary-correct"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
assert isinstance(data, list), 'Summary must be a list'
assert len(data) > 0, 'Summary is empty'
for item in data:
    assert 'filename' in item, 'Missing filename'
    assert 'line_count' in item, 'Missing line_count'
    assert 'word_count' in item, 'Missing word_count'
print(f'✓ Summary has {len(data)} files')
"
"""
trigger = "on_stop"
description = "Summary must be a list of file stats"
```

**Design choices:**
- Uses official MCP filesystem server
- Agent gets standard file operations (list, read, write)
- No custom tool code needed
- MCP server handles all file I/O

---

## Recipe 8: Research Task

**Use case:** Information gathering and documentation.

```toml
name = "research-task"
description = "Research and document findings"

goal = """
Research the codebase and answer these questions:

1. What files exist in the project?
2. What is the main entry point?
3. What dependencies are listed?
4. What testing framework is used?

Create a report (RESEARCH.md) with your findings in markdown format.

Use headings for each question, and provide specific file names and line numbers where relevant.

Stop once RESEARCH.md is created.
"""

[model]
name = "anthropic/claude-sonnet-4.6"
temperature = 0.5  # Lower temperature for factual research
max_tokens = 4000

[environment]
type = "local"
root = "./workspace"

[boundary]
allow_write = ["RESEARCH.md"]
allow_read = ["**/*"]  # Can read any file for research

[context]
max_tokens = 100000  # Higher budget for exploration
max_cost = "$2.00"
max_steps = 30

[[verifiers]]
name = "report-exists"
command = "test -f RESEARCH.md"
trigger = "on_stop"
description = "RESEARCH.md must exist"

[[verifiers]]
name = "report-complete"
command = """
grep -q '## What files exist' RESEARCH.md && \
grep -q '## What is the main entry point' RESEARCH.md && \
grep -q '## What dependencies' RESEARCH.md && \
grep -q '## What testing framework' RESEARCH.md
"""
trigger = "on_stop"
description = "Report must have all four required sections"
```

**Design choices:**
- Lower temperature (0.5) for factual accuracy
- `allow_read = ["**/*"]` permits full codebase exploration
- Higher token budget for thorough investigation
- Verifier checks that all questions are addressed

---

## Common Patterns Summary

### Pattern: File Existence → Validation → Correctness

```toml
[[verifiers]]
name = "exists"
command = "test -f output.json"
# ...

[[verifiers]]
name = "valid-format"
command = "python -m json.tool output.json > /dev/null"
# ...

[[verifiers]]
name = "correct-data"
command = "./validate_data.sh"
# ...
```

### Pattern: Re-observation for Long Tasks

```toml
re_observation = [
    "ls -1 *.py 2>/dev/null | cat",
    "git status --short"
]
```

### Pattern: Scoped Boundaries

```toml
[boundary]
allow_write = ["output/*", "logs/*.txt"]  # Specific paths only
allow_read = ["data/*.csv"]               # Input data only
network = "deny"                          # No external access
```

### Pattern: Token Budget for Task Complexity

- Simple (1-5 steps): `max_tokens = 20000`
- Medium (5-15 steps): `max_tokens = 80000`
- Complex (15-30 steps): `max_tokens = 150000`

Always include safety margin (5-8x estimated usage).
