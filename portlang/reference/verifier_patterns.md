# Verifier Patterns

This guide contains real-world verifier examples for common portlang tasks.

## Verifier Types

portlang supports four verifier types. `type` is optional and defaults to `"shell"`.

| Type | Use when | Key fields |
|------|----------|-----------|
| `shell` | Custom logic, running tests, git checks | `command` |
| `json` | Validating JSON structure/schema | `file`, `schema` |
| `levenshtein` | Fuzzy text match (tolerates typos/formatting) | `file`, `expected`, `threshold` |
| `semantic` | Meaning-based match (paraphrase tolerance) | `file`, `expected`, `threshold`, `embedding_model` |

All types share: `name` (required), `trigger` (`on_stop`/`always`/`on_write`), `description`.

## Core Concept

Verifiers are runtime reward signals, not post-hoc checks. Their output enters the context window and steers agent behavior. Weak verifiers lead to weak solutions.

**Key principle:** Verifiers should be:
- **Precise:** Clear success criteria
- **Fast:** Run in <5 seconds when possible
- **Informative:** Descriptive error messages
- **Progressive:** Simple checks before complex ones

## Basic File Verifiers

### 1. File Existence

```toml
[[verifier]]
name = "output-exists"
command = "test -f output.json"
trigger = "on_stop"
description = "output.json must exist"
```

### 2. Multiple Files Exist

```toml
[[verifier]]
name = "all-files-exist"
command = "test -f analyzer.py && test -f test_analyzer.py && test -f requirements.txt"
trigger = "on_stop"
description = "All required files must exist: analyzer.py, test_analyzer.py, requirements.txt"
```

### 3. Directory Structure

```toml
[[verifier]]
name = "directory-structure"
command = """
test -d src && test -d tests && test -f src/__init__.py && test -f tests/__init__.py
"""
trigger = "on_stop"
description = "Project structure: src/ and tests/ directories with __init__.py files"
```

## JSON and Data Validation

### 4. Valid JSON Syntax

```toml
[[verifier]]
name = "valid-json"
command = "python -m json.tool output.json > /dev/null"
trigger = "on_stop"
description = "output.json must be valid JSON"
```

### 5. JSON Schema Validation

```toml
[[verifier]]
name = "schema-valid"
command = """
python -c "
import json
with open('output.json') as f:
    data = json.load(f)
# Check required fields
assert 'name' in data, 'Missing required field: name'
assert 'age' in data, 'Missing required field: age'
assert 'email' in data, 'Missing required field: email'
# Check types
assert isinstance(data['age'], int), 'age must be integer'
assert isinstance(data['email'], str), 'email must be string'
print('✓ Schema valid')
"
"""
trigger = "on_stop"
description = "JSON must have name, age (int), and email (string) fields"
```

### 6. Data Range Validation

```toml
[[verifier]]
name = "data-ranges"
command = """
python -c "
import json
with open('results.json') as f:
    data = json.load(f)
# Check value ranges
assert 0 <= data['score'] <= 100, f\"Score {data['score']} out of range [0, 100]\"
assert data['count'] > 0, 'Count must be positive'
assert len(data['items']) >= 5, f\"Expected at least 5 items, got {len(data['items'])}\"
print('✓ All values in valid ranges')
"
"""
trigger = "on_stop"
description = "Data must be in valid ranges: score [0-100], count > 0, items >= 5"
```

### 7. CSV Validation

```toml
[[verifier]]
name = "valid-csv"
command = """
python -c "
import csv
with open('output.csv') as f:
    reader = csv.DictReader(f)
    rows = list(reader)
    assert len(rows) > 0, 'CSV is empty'
    required_cols = ['name', 'value', 'category']
    actual_cols = reader.fieldnames
    assert all(col in actual_cols for col in required_cols), \
        f'Missing columns. Required: {required_cols}, Found: {actual_cols}'
print(f'✓ Valid CSV with {len(rows)} rows')
"
"""
trigger = "on_stop"
description = "CSV must have columns: name, value, category with at least one row"
```

## Python Code Verification

### 8. Syntax Validity

```toml
[[verifier]]
name = "python-syntax"
command = "python -m py_compile analyzer.py"
trigger = "on_stop"
description = "analyzer.py must be syntactically valid Python"
```

### 9. Run Tests with pytest

```toml
[[verifier]]
name = "tests-pass"
command = "python -m pytest test_analyzer.py -v 2>&1"
trigger = "on_stop"
description = "All tests in test_analyzer.py must pass"
```

### 10. Run Tests with Coverage Threshold

```toml
[[verifier]]
name = "tests-with-coverage"
command = """
python -m pytest tests/ --cov=src --cov-report=term --cov-fail-under=80 2>&1
"""
trigger = "on_stop"
description = "All tests must pass with at least 80% code coverage"
```

### 11. Type Checking with mypy

```toml
[[verifier]]
name = "type-check"
command = "python -m mypy src/ --strict 2>&1"
trigger = "on_stop"
description = "Code must pass strict mypy type checking"
```

### 12. Linting with ruff

```toml
[[verifier]]
name = "lint-check"
command = "python -m ruff check src/ 2>&1"
trigger = "on_stop"
description = "Code must pass ruff linting with no errors"
```

## Git and Version Control

### 13. No Uncommitted Changes

```toml
[[verifier]]
name = "clean-git"
command = "git diff --exit-code"
trigger = "on_stop"
description = "No uncommitted changes allowed"
```

### 14. Only Specific Files Modified

```toml
[[verifier]]
name = "scope-guard"
command = """
git diff --name-only | grep -qvE '^(auth\\.py|tests/)' && exit 1 || exit 0
"""
trigger = "on_stop"
description = "Only auth.py and tests/ should be modified"
```

### 15. Commit Message Format

```toml
[[verifier]]
name = "commit-format"
command = """
git log -1 --pretty=%B | grep -qE '^(feat|fix|docs|refactor|test):\\s.+' || \
(echo 'Commit message must start with feat:, fix:, docs:, refactor:, or test:' && exit 1)
"""
trigger = "on_stop"
description = "Commit message must follow conventional commits format"
```

## Functional and Integration Tests

### 16. Script Execution Test

```toml
[[verifier]]
name = "script-runs"
command = """
python analyzer.py sample.txt output.json && test -f output.json
"""
trigger = "on_stop"
description = "analyzer.py must execute successfully and create output.json"
```

### 17. Output Correctness Test

```toml
[[verifier]]
name = "correct-output"
command = """
python analyzer.py test_input.txt test_output.json
python -c "
import json
with open('test_output.json') as f:
    result = json.load(f)
with open('expected.json') as f:
    expected = json.load(f)
assert result == expected, f'Output mismatch: {result} != {expected}'
print('✓ Output matches expected')
"
"""
trigger = "on_stop"
description = "analyzer.py output must match expected results"
```

### 18. Performance Benchmark

```toml
[[verifier]]
name = "performance"
command = """
time_output=$(time python analyzer.py large_file.txt output.json 2>&1)
python -c "
import re
output = '''$time_output'''
match = re.search(r'real\\s+(\\d+)m([\\d.]+)s', output)
if match:
    minutes, seconds = float(match.group(1)), float(match.group(2))
    total_seconds = minutes * 60 + seconds
    assert total_seconds < 30, f'Execution took {total_seconds}s, must be < 30s'
    print(f'✓ Performance acceptable: {total_seconds:.2f}s')
"
"""
trigger = "on_stop"
description = "Script must complete in under 30 seconds"
```

## Multi-Step Verifiers

### 19. Multi-Layer Data Pipeline Verification

```toml
# Layer 1: File exists
[[verifier]]
name = "output-exists"
command = "test -f summary.json"
trigger = "on_stop"
description = "summary.json must exist"

# Layer 2: Valid JSON
[[verifier]]
name = "valid-json"
command = "python -m json.tool summary.json > /dev/null"
trigger = "on_stop"
description = "summary.json must be valid JSON"

# Layer 3: Required fields
[[verifier]]
name = "required-fields"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
required = ['total_revenue', 'regions', 'top_product']
assert all(k in data for k in required), \
    f\"Missing fields. Required: {required}, Found: {list(data.keys())}\"
print('✓ All required fields present')
"
"""
trigger = "on_stop"
description = "JSON must have total_revenue, regions, and top_product fields"

# Layer 4: Data integrity
[[verifier]]
name = "data-integrity"
command = """
python -c "
import json
with open('summary.json') as f:
    data = json.load(f)
# Type checks
assert isinstance(data['total_revenue'], (int, float)), 'total_revenue must be numeric'
assert isinstance(data['regions'], list), 'regions must be a list'
assert len(data['regions']) == 4, f\"Expected 4 regions, got {len(data['regions'])}\"
# Value checks
assert data['total_revenue'] > 0, 'total_revenue must be positive'
print('✓ Data integrity verified')
"
"""
trigger = "on_stop"
description = "Data must pass integrity checks: correct types and valid values"
```

### 20. Complete Web Scraper Verification

```toml
[[verifier]]
name = "scraper-output"
command = "test -f scraped_data.json"
trigger = "on_stop"
description = "scraped_data.json must exist"

[[verifier]]
name = "valid-json"
command = "python -m json.tool scraped_data.json > /dev/null"
trigger = "on_stop"
description = "Output must be valid JSON"

[[verifier]]
name = "data-completeness"
command = """
python -c "
import json
with open('scraped_data.json') as f:
    data = json.load(f)
assert isinstance(data, list), 'Data must be a list'
assert len(data) >= 10, f'Expected at least 10 items, got {len(data)}'
# Check each item
for i, item in enumerate(data):
    assert 'title' in item, f'Item {i} missing title'
    assert 'url' in item, f'Item {i} missing url'
    assert 'date' in item, f'Item {i} missing date'
print(f'✓ {len(data)} items scraped, all complete')
"
"""
trigger = "on_stop"
description = "At least 10 items, each with title, url, and date"

[[verifier]]
name = "no-duplicates"
command = """
python -c "
import json
with open('scraped_data.json') as f:
    data = json.load(f)
urls = [item['url'] for item in data]
assert len(urls) == len(set(urls)), 'Duplicate URLs found'
print('✓ No duplicates')
"
"""
trigger = "on_stop"
description = "No duplicate URLs in scraped data"
```

## JSON, Levenshtein, and Semantic Verifiers

### 21. JSON Structure Validation (no jq/python needed)

```toml
[[verifier]]
type = "json"
name = "valid-schema"
file = "output.json"
schema = '{"type": "object", "required": ["status", "count", "items"], "properties": {"status": {"type": "string", "enum": ["ok", "error"]}, "count": {"type": "integer"}, "items": {"type": "array"}}}'
trigger = "on_stop"
description = "output.json must match required schema"
```

Omit `schema` to simply check the file contains valid JSON:
```toml
[[verifier]]
type = "json"
name = "valid-json"
file = "output.json"
trigger = "on_stop"
description = "output.json must be valid JSON"
```

### 22. Levenshtein (fuzzy text match)

Use when exact string match is too strict — tolerates whitespace, punctuation, or minor wording differences.

```toml
[[verifier]]
type = "levenshtein"
name = "output-close"
file = "answer.txt"
expected = "The capital of France is Paris."
threshold = 0.9
trigger = "on_stop"
description = "Answer must be at least 90% similar to expected text"
```

`threshold = 1.0` (default) requires exact match. Lower values allow more variation.

### 23. Semantic Similarity

Use when the agent should convey the right *meaning* without using the exact same words.

```toml
[[verifier]]
type = "semantic"
name = "correct-conclusion"
file = "summary.txt"
expected = "The experiment demonstrates that the treatment significantly reduced symptoms."
threshold = 0.85
trigger = "on_stop"
description = "Summary must convey the correct experimental conclusion"
```

**Available embedding models** (downloaded from HuggingFace on first use, no API key):
- `bge-small-en-v1.5` (default, ~67 MB)
- `all-minilm-l6-v2`
- `nomic-embed-text-v1.5`

**Use an OpenAI-compatible endpoint instead:**
```toml
[[verifier]]
type = "semantic"
name = "meaning-check"
file = "output.txt"
expected = "Revenue increased by approximately 15% year-over-year."
threshold = 0.88
embedding_url = "https://api.openai.com/v1/embeddings"
trigger = "on_stop"
description = "Output must match the expected financial finding"
```
Reads `EMBEDDING_API_KEY` or `OPENAI_API_KEY` from the environment.

### 24. Combining Typed Verifiers (progressive pipeline)

```toml
# Layer 1: File is valid JSON
[[verifier]]
type = "json"
name = "valid-json"
file = "report.json"
trigger = "on_stop"
description = "report.json must be valid JSON"

# Layer 2: JSON matches required schema
[[verifier]]
type = "json"
name = "schema-check"
file = "report.json"
schema = '{"type": "object", "required": ["title", "body", "score"]}'
trigger = "on_stop"
description = "report.json must have title, body, and score fields"

# Layer 3: The written content conveys the right meaning
[[verifier]]
type = "semantic"
name = "correct-meaning"
file = "report.json"
expected = "The analysis found strong positive correlation between variables."
threshold = 0.8
trigger = "on_stop"
description = "Report must convey the correct statistical finding"
```

## Best Practices Summary

1. **Order matters:** Verifiers run sequentially. Put simple checks first.
2. **Fail fast:** Exit on first failure with clear error message.
3. **Be specific:** Describe exactly what's wrong, not just "invalid".
4. **Use exit codes:** 0 = pass, non-zero = fail.
5. **Capture stderr:** Use `2>&1` to see error details.
6. **Test verifiers:** Run commands manually before adding to field.toml.
7. **Multi-line commands:** Use triple quotes for complex Python/bash.
8. **Escape quotes:** In Python strings within TOML, use `'` or `\\"`.

## Shell Scripting Tips

For complex verifiers, create a separate script:

**verify_output.sh:**
```bash
#!/bin/bash
set -e  # Exit on any error

# Check file exists
test -f output.json || { echo "Error: output.json not found"; exit 1; }

# Check valid JSON
python -m json.tool output.json > /dev/null || \
    { echo "Error: Invalid JSON"; exit 1; }

# Check schema
python -c "
import json
with open('output.json') as f:
    data = json.load(f)
assert 'results' in data, 'Missing results field'
assert len(data['results']) > 0, 'Results empty'
" || { echo "Error: Schema validation failed"; exit 1; }

echo "✓ All checks passed"
```

**Use in field.toml:**
```toml
[[verifier]]
name = "comprehensive-check"
command = "./verify_output.sh"
trigger = "on_stop"
description = "Output must pass all validation checks"
```

Make executable: `chmod +x verify_output.sh`

## Debugging Failed Verifiers

If a verifier fails:

1. **Run command manually:**
   ```bash
   cd workspace
   python -m json.tool output.json
   ```

2. **Check exit code:**
   ```bash
   echo $?  # 0 = success, non-zero = failure
   ```

3. **Add debug output:**
   ```bash
   python -c "print('Debug: starting check'); import json; ..."
   ```

4. **Use portlang replay:**
   ```bash
   portlang replay <trajectory-id>
   # See verifier output at the step it failed
   ```
