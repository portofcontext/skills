# Trajectory Analysis

Trajectories are the complete event logs of agent runs. This guide shows you how to analyze trajectories for debugging, optimization, and understanding agent behavior.

## Core Concepts

**What is a trajectory?**

A trajectory is a complete record of an agent run:
- Every step taken
- Every action (tool call, file write, etc.)
- Every environment response
- Every verifier result
- Token and cost usage
- Final outcome

**Where are trajectories stored?**

```
~/.portlang/trajectories/
  ├── field-name-1/
  │   ├── abc123.json
  │   ├── def456.json
  │   └── ...
  └── field-name-2/
      ├── ghi789.json
      └── ...
```

Each field has a directory, each run creates a JSON file with unique ID.

**Why trajectories matter:**

Agent systems are non-deterministic. You can't debug by running once. You need to reason about distributions:
- What percentage of runs succeed?
- Where do failures typically occur?
- Which tools correlate with success?
- How much variance is there in token usage?

Trajectories provide the data to answer these questions.

## Trajectory JSON Structure

### Top-Level Fields

```json
{
  "id": "abc123def456",
  "field_name": "code-task",
  "started_at": "2025-01-15T10:30:00Z",
  "completed_at": "2025-01-15T10:32:30Z",
  "outcome": "Converged",
  "total_steps": 8,
  "total_tokens": 12450,
  "total_cost": 0.42,
  "steps": [ /* array of step objects */ ],
  "verifier_results": [ /* final verifier results */ ]
}
```

**Outcome types:**
- `"Converged"` - All verifiers passed, agent stopped successfully
- `"BudgetExhausted"` - Token limit reached
- `"StepLimitReached"` - Max steps exceeded
- `"CostLimitReached"` - Cost budget exhausted
- `"VerifierFailed"` - Agent stopped but verifier failed
- `"LoopDetected"` - Agent repeated same action too many times

### Step Structure

Each step records what happened during one agent turn:

```json
{
  "step_number": 3,
  "timestamp": "2025-01-15T10:31:15Z",
  "action": {
    "type": "ToolCall",
    "tool": "write",
    "arguments": {
      "path": "analyzer.py",
      "content": "..."
    }
  },
  "response": {
    "success": true,
    "output": "File written: analyzer.py"
  },
  "verifiers": [],
  "tokens_used": 1850,
  "cost": 0.055,
  "cumulative_tokens": 5600,
  "cumulative_cost": 0.18
}
```

**Action types:**
- `"ToolCall"` - Agent called a tool (read, write, custom tool)
- `"Stop"` - Agent signaled completion
- `"Thinking"` - Internal deliberation (future)

### Verifier Results

When verifiers run (typically at `on_stop`):

```json
{
  "name": "tests-pass",
  "command": "python -m pytest test_analyzer.py -v",
  "passed": false,
  "exit_code": 1,
  "stdout": "...",
  "stderr": "FAILED test_analyzer.py::test_word_count - AssertionError",
  "duration_ms": 342
}
```

## Analyzing Individual Trajectories

### Using portlang replay

**Interactive step-through:**

```bash
portlang replay abc123def456
```

**Output:**
```
Trajectory: abc123def456
Field: code-task
Outcome: Converged
Total steps: 8
Total tokens: 12,450
Total cost: $0.42

Step 1/8:
  Action: read(file="requirements.txt")
  Response: File not found
  Tokens: 850 (cumulative: 850)
  Cost: $0.025

Step 2/8:
  Action: write(file="analyzer.py", content="...")
  Response: File written
  Tokens: 1200 (cumulative: 2050)
  Cost: $0.036

[Press Enter for next step, 'q' to quit]
```

**JSON output:**

```bash
portlang replay abc123def456 --format json > trajectory.json
```

Exports complete trajectory as JSON for programmatic analysis.

### Finding Failure Points

**Pattern:** Look for the step where things went wrong.

**Example:**
```bash
portlang replay abc123def456 | grep -A 5 "Verifier"
```

Shows verifier results and context.

**Common failure patterns:**

1. **Verifier cascade failure:**
   - Step N: Agent stops
   - Verifier 1: Pass (file exists)
   - Verifier 2: Fail (invalid JSON)
   - **Diagnosis:** Agent created file but with wrong format

2. **Boundary violation loop:**
   - Step 1: write(file="output.txt")
   - Response: Permission denied
   - Step 2: write(file="output.txt")
   - Response: Permission denied
   - Step 3: write(file="output.txt")
   - **Diagnosis:** Agent doesn't understand boundary, needs clearer goal or different boundary

3. **Token exhaustion:**
   - Step 20: Total tokens: 78,500
   - Step 21: Budget exhausted
   - Outcome: BudgetExhausted
   - **Diagnosis:** Task too complex for budget, or re-observation too verbose

4. **Tool error spiral:**
   - Step 5: custom_tool(...)
   - Response: Error: missing parameter
   - Step 6: custom_tool(...)
   - Response: Error: invalid type
   - Step 7: custom_tool(...)
   - **Diagnosis:** Tool error messages not clear enough, or tool input schema issue

## Comparing Trajectories

### Using portlang diff

**Structural comparison:**

```bash
portlang diff abc123 def456
```

**Output:**
```
Comparing trajectories:
  A: abc123 (Converged)
  B: def456 (VerifierFailed)

Steps aligned:
  Step 1: SAME - read(file="data.csv")
  Step 2: SAME - write(file="output.json", ...)
  Step 3: SAME - Stop

Verifiers:
  output-exists: BOTH PASS
  valid-json: BOTH PASS
  schema-valid: A PASS, B FAIL

First divergence: Verifier 'schema-valid'
  A: Exit code 0
  B: Exit code 1, stderr: "AssertionError: Missing field 'total'"

Analysis: Both runs took same actions but produced different outputs.
Suggests non-deterministic agent behavior in content generation.
```

**Use cases:**
- Debug non-determinism: Why did the same field produce different results?
- Regression analysis: Compare before/after changes to field.toml
- Convergence analysis: Find where successful and failed runs diverge

### Text vs JSON Output

```bash
# Human-readable
portlang diff abc123 def456

# Machine-readable
portlang diff abc123 def456 --format json
```

JSON output structure:
```json
{
  "trajectory_a": "abc123",
  "trajectory_b": "def456",
  "aligned_steps": [
    {"step": 1, "match": "same", "action_a": {...}, "action_b": {...}},
    {"step": 2, "match": "different", "action_a": {...}, "action_b": {...}}
  ],
  "first_divergence": {
    "step": 2,
    "type": "action",
    "details": "..."
  }
}
```

## Analyzing Multiple Trajectories

### Using portlang report

**Aggregate analysis across all runs of a field:**

```bash
portlang report code-task
```

**Output:**
```
Field: code-task
Total runs: 25
Converged: 20 (80%)
Failed: 5 (20%)

Token usage:
  Median: 12,450
  p90: 18,200
  p99: 22,100
  Max: 24,800

Cost distribution:
  Median: $0.42
  p90: $0.58
  p99: $0.71

Step count:
  Median: 8
  p90: 12
  p99: 15

Tool usage:
  read: 100% of runs
  write: 96% of runs (100% of successes, 80% of failures)
  glob: 40% of runs (25% of successes, 80% of failures)

Verifier pass rates:
  output-exists: 96% (24/25)
  valid-json: 84% (21/25)
  tests-pass: 80% (20/25)

Adaptation insights:
  - Tool 'glob' correlates with failure (used in 80% of failures)
  - Consider removing 'glob' or clarifying when to use it
  - Verifier 'valid-json' fails 16% of time, consider stronger prompt guidance
```

**Actionable insights:**
1. Tool usage patterns show which tools help vs hurt
2. Verifier pass rates show which checks are weak
3. Budget utilization shows if limits are too tight/loose
4. Convergence rate shows overall field reliability

### Custom Analysis Scripts

For advanced analysis, extract trajectory data programmatically:

**Load trajectory JSON:**

```python
import json
from pathlib import Path

trajectory_path = Path.home() / ".portlang" / "trajectories" / "code-task" / "abc123.json"

with open(trajectory_path) as f:
    trajectory = json.load(f)

print(f"Outcome: {trajectory['outcome']}")
print(f"Steps: {trajectory['total_steps']}")
print(f"Tokens: {trajectory['total_tokens']}")

# Analyze steps
for step in trajectory['steps']:
    print(f"Step {step['step_number']}: {step['action']['type']}")
```

**Analyze token usage across runs:**

```python
import json
from pathlib import Path
import statistics

# Load all trajectories for a field
field_dir = Path.home() / ".portlang" / "trajectories" / "code-task"
trajectories = []

for trajectory_file in field_dir.glob("*.json"):
    with open(trajectory_file) as f:
        trajectories.append(json.load(f))

# Extract token usage
token_counts = [t['total_tokens'] for t in trajectories]

print(f"Total runs: {len(trajectories)}")
print(f"Mean tokens: {statistics.mean(token_counts):.0f}")
print(f"Median tokens: {statistics.median(token_counts):.0f}")
print(f"Std dev: {statistics.stdev(token_counts):.0f}")

# Find outliers (>2 std dev from mean)
mean = statistics.mean(token_counts)
stddev = statistics.stdev(token_counts)
outliers = [t for t in trajectories if abs(t['total_tokens'] - mean) > 2 * stddev]

print(f"\nOutliers: {len(outliers)}")
for t in outliers:
    print(f"  {t['id']}: {t['total_tokens']} tokens, outcome: {t['outcome']}")
```

## Advanced Analysis Patterns

### 1. Convergence by Tool Usage

**Question:** Do certain tool combinations predict success?

```python
from collections import Counter

# Group by outcome
converged = [t for t in trajectories if t['outcome'] == 'Converged']
failed = [t for t in trajectories if t['outcome'] != 'Converged']

def get_tools_used(trajectory):
    """Extract unique tools used in a trajectory."""
    tools = set()
    for step in trajectory['steps']:
        if step['action']['type'] == 'ToolCall':
            tools.add(step['action']['tool'])
    return frozenset(tools)

# Count tool combinations
converged_tools = Counter([get_tools_used(t) for t in converged])
failed_tools = Counter([get_tools_used(t) for t in failed])

print("Most common tool sets in successful runs:")
for toolset, count in converged_tools.most_common(3):
    print(f"  {set(toolset)}: {count} runs")

print("\nMost common tool sets in failed runs:")
for toolset, count in failed_tools.most_common(3):
    print(f"  {set(toolset)}: {count} runs")
```

### 2. Divergence Clustering

**Question:** Where do most failures happen?

```python
# Track which step failures occur
failure_steps = []
for t in failed:
    failure_steps.append(t['total_steps'])

import statistics
print(f"Failures occur at step (median): {statistics.median(failure_steps)}")
print(f"Range: {min(failure_steps)} - {max(failure_steps)}")

# Look at what happens at typical failure step
typical_failure_step = int(statistics.median(failure_steps))
print(f"\nActions at step {typical_failure_step} in failed runs:")
for t in failed:
    if t['total_steps'] >= typical_failure_step:
        step = t['steps'][typical_failure_step - 1]
        print(f"  {t['id']}: {step['action']['type']} - {step['action'].get('tool', 'N/A')}")
```

### 3. Cost Efficiency Analysis

**Question:** What's the cost per successful outcome?

```python
converged_costs = [t['total_cost'] for t in converged]
total_cost = sum(t['total_cost'] for t in trajectories)
total_converged = len(converged)

avg_cost_per_success = statistics.mean(converged_costs)
cost_per_success_with_failures = total_cost / total_converged

print(f"Average cost per successful run: ${avg_cost_per_success:.2f}")
print(f"Average cost per success (including failures): ${cost_per_success_with_failures:.2f}")
print(f"Efficiency ratio: {(avg_cost_per_success / cost_per_success_with_failures) * 100:.1f}%")
```

### 4. Verifier Signal Quality

**Question:** Which verifiers provide useful signal?

```python
# Count verifier pass rates across all runs
verifier_stats = {}

for t in trajectories:
    for v in t.get('verifier_results', []):
        name = v['name']
        if name not in verifier_stats:
            verifier_stats[name] = {'pass': 0, 'fail': 0}

        if v['passed']:
            verifier_stats[name]['pass'] += 1
        else:
            verifier_stats[name]['fail'] += 1

# Calculate signal quality
for name, stats in verifier_stats.items():
    total = stats['pass'] + stats['fail']
    pass_rate = stats['pass'] / total
    # Good signal: 50-90% pass rate
    # Weak signal: >95% or <10% pass rate
    signal_quality = "GOOD" if 0.5 <= pass_rate <= 0.9 else "WEAK"
    print(f"{name}: {pass_rate*100:.1f}% pass rate - {signal_quality}")
```

## Debugging Workflows

### Workflow 1: Non-Determinism Debugging

**Scenario:** Same field, different outcomes

```bash
# Run multiple times
portlang converge field.toml -n 5

# Identify divergent runs
portlang list code-task

# Compare successful vs failed
portlang diff abc123 def456

# Look for:
# - Different tool calls at same step
# - Different file contents written
# - Different verifier results

# Fix:
# - Strengthen verifiers (make expectations explicit)
# - Reduce temperature (if too high)
# - Add re-observation (keep context fresh)
```

### Workflow 2: Budget Optimization

**Scenario:** Runs hitting token limit

```bash
# Analyze token usage
portlang report code-task

# Look at p90, p99 token usage
# If often hitting limit, either:
# - Increase max_tokens
# - Reduce re-observation frequency
# - Simplify goal prompt

# Compare high-token vs low-token runs
portlang diff <high-token-run> <low-token-run>

# Look for:
# - Extra tool calls in high-token run
# - Repeated actions (loops)
# - Large environment responses
```

### Workflow 3: Verifier Cascade Analysis

**Scenario:** Some runs fail late-stage verifiers

```bash
# Replay failed run
portlang replay abc123

# Note which verifier failed
# Example: schema-valid passes, but data-integrity fails

# This means:
# - Early verifiers too weak (let bad data through)
# - Late verifier expectations not in prompt

# Fix:
# - Strengthen earlier verifier
# - Add schema check in prompt
# - Add example of expected output
```

## Best Practices

1. **Always run multiple times:** One run tells you nothing about reliability
2. **Use portlang converge:** Automated multi-run with statistics
3. **Compare successes and failures:** Divergence analysis reveals issues
4. **Track trends over time:** Are changes improving convergence?
5. **Export for analysis:** Use `--format json` for custom scripts
6. **Clean up old trajectories:** `rm -rf ~/.portlang/trajectories/<old-field>/`
7. **Archive important runs:** Copy trajectory JSON before cleanup
8. **Document findings:** Keep notes on what divergence patterns mean

## Trajectory Data Privacy

**What's recorded:**
- All prompts and agent responses
- All tool calls and results
- All file contents written
- All verifier output

**Security considerations:**
- Trajectories may contain sensitive data (API keys, credentials)
- Stored locally in `~/.portlang/trajectories/`
- Never uploaded anywhere by portlang
- Review before sharing trajectory JSON files
- Use `.gitignore` to exclude `~/.portlang/` from repos

**Cleanup:**
```bash
# Remove all trajectories for a field
rm -rf ~/.portlang/trajectories/code-task/

# Remove all trajectories
rm -rf ~/.portlang/trajectories/
```
