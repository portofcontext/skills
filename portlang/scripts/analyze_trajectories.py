#!/usr/bin/env python3
"""
analyze_trajectories.py - Multi-trajectory statistical analysis

Analyzes all trajectories for a field and outputs statistics.

Usage:
    python analyze_trajectories.py <field-name>
    python analyze_trajectories.py <field-name> --format json
    python analyze_trajectories.py <field-name> --output report.json
"""

import json
import sys
import statistics
from pathlib import Path
from collections import Counter, defaultdict
from typing import List, Dict, Any
import argparse


def load_trajectories(field_name: str) -> List[Dict[str, Any]]:
    """Load all trajectories for a given field."""
    trajectory_dir = Path.home() / ".portlang" / "trajectories" / field_name

    if not trajectory_dir.exists():
        print(f"Error: No trajectories found for field '{field_name}'", file=sys.stderr)
        print(f"Expected directory: {trajectory_dir}", file=sys.stderr)
        sys.exit(1)

    trajectories = []
    for trajectory_file in trajectory_dir.glob("*.json"):
        try:
            with open(trajectory_file) as f:
                trajectories.append(json.load(f))
        except json.JSONDecodeError:
            print(f"Warning: Could not parse {trajectory_file}", file=sys.stderr)
        except Exception as e:
            print(f"Warning: Error loading {trajectory_file}: {e}", file=sys.stderr)

    if not trajectories:
        print(
            f"Error: No valid trajectories found in {trajectory_dir}", file=sys.stderr
        )
        sys.exit(1)

    return trajectories


def calculate_percentile(data: List[float], percentile: int) -> float:
    """Calculate the nth percentile of a dataset."""
    if not data:
        return 0.0
    sorted_data = sorted(data)
    index = (percentile / 100) * (len(sorted_data) - 1)
    lower = int(index)
    upper = min(lower + 1, len(sorted_data) - 1)
    weight = index - lower
    return sorted_data[lower] * (1 - weight) + sorted_data[upper] * weight


def analyze_token_usage(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze token usage patterns."""
    token_counts = [t.get("total_tokens", 0) for t in trajectories]

    return {
        "median": int(statistics.median(token_counts)) if token_counts else 0,
        "mean": int(statistics.mean(token_counts)) if token_counts else 0,
        "p90": int(calculate_percentile(token_counts, 90)),
        "p99": int(calculate_percentile(token_counts, 99)),
        "min": min(token_counts) if token_counts else 0,
        "max": max(token_counts) if token_counts else 0,
    }


def analyze_cost(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze cost distribution."""
    costs = [t.get("total_cost", 0.0) for t in trajectories]

    return {
        "median": round(statistics.median(costs), 2) if costs else 0.0,
        "mean": round(statistics.mean(costs), 2) if costs else 0.0,
        "p90": round(calculate_percentile(costs, 90), 2),
        "p99": round(calculate_percentile(costs, 99), 2),
        "min": round(min(costs), 2) if costs else 0.0,
        "max": round(max(costs), 2) if costs else 0.0,
        "total": round(sum(costs), 2),
    }


def analyze_steps(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze step count distribution."""
    step_counts = [t.get("total_steps", 0) for t in trajectories]

    return {
        "median": int(statistics.median(step_counts)) if step_counts else 0,
        "mean": round(statistics.mean(step_counts), 1) if step_counts else 0,
        "p90": int(calculate_percentile(step_counts, 90)),
        "p99": int(calculate_percentile(step_counts, 99)),
        "min": min(step_counts) if step_counts else 0,
        "max": max(step_counts) if step_counts else 0,
    }


def analyze_outcomes(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze run outcomes."""
    outcome_counts = Counter(t.get("outcome", "Unknown") for t in trajectories)
    total = len(trajectories)

    converged = outcome_counts.get("Converged", 0)
    convergence_rate = (converged / total * 100) if total > 0 else 0

    return {
        "total_runs": total,
        "converged": converged,
        "convergence_rate": round(convergence_rate, 1),
        "outcomes": dict(outcome_counts),
    }


def analyze_tool_usage(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze which tools are used and correlate with success."""
    tool_usage = defaultdict(lambda: {"total": 0, "in_success": 0, "in_failure": 0})

    for trajectory in trajectories:
        is_success = trajectory.get("outcome") == "Converged"
        tools_used = set()

        for step in trajectory.get("steps", []):
            action = step.get("action", {})
            if action.get("type") == "ToolCall":
                tool = action.get("tool")
                if tool:
                    tools_used.add(tool)

        for tool in tools_used:
            tool_usage[tool]["total"] += 1
            if is_success:
                tool_usage[tool]["in_success"] += 1
            else:
                tool_usage[tool]["in_failure"] += 1

    # Calculate usage percentages
    total_runs = len(trajectories)
    result = {}

    for tool, stats in tool_usage.items():
        success_rate = (
            (stats["in_success"] / stats["total"] * 100) if stats["total"] > 0 else 0
        )
        usage_rate = stats["total"] / total_runs * 100

        result[tool] = {
            "total_uses": stats["total"],
            "usage_rate": round(usage_rate, 1),
            "in_success": stats["in_success"],
            "in_failure": stats["in_failure"],
            "success_rate": round(success_rate, 1),
        }

    return result


def analyze_verifiers(trajectories: List[Dict]) -> Dict[str, Any]:
    """Analyze verifier pass rates."""
    verifier_stats = defaultdict(lambda: {"pass": 0, "fail": 0})

    for trajectory in trajectories:
        for verifier in trajectory.get("verifier_results", []):
            name = verifier.get("name")
            if name:
                if verifier.get("passed"):
                    verifier_stats[name]["pass"] += 1
                else:
                    verifier_stats[name]["fail"] += 1

    result = {}
    for name, stats in verifier_stats.items():
        total = stats["pass"] + stats["fail"]
        pass_rate = (stats["pass"] / total * 100) if total > 0 else 0

        # Assess signal quality
        # Good signal: 50-90% pass rate (provides useful feedback)
        # Weak signal: >95% or <10% (too easy or too hard, not steering behavior)
        if 50 <= pass_rate <= 90:
            signal_quality = "GOOD"
        else:
            signal_quality = "WEAK"

        result[name] = {
            "pass": stats["pass"],
            "fail": stats["fail"],
            "total": total,
            "pass_rate": round(pass_rate, 1),
            "signal_quality": signal_quality,
        }

    return result


def print_text_report(analysis: Dict[str, Any], field_name: str):
    """Print human-readable analysis report."""
    print(f"\n{'='*60}")
    print(f"Trajectory Analysis: {field_name}")
    print(f"{'='*60}\n")

    # Outcomes
    outcomes = analysis["outcomes"]
    print(f"Total Runs: {outcomes['total_runs']}")
    print(f"Converged: {outcomes['converged']} ({outcomes['convergence_rate']}%)")
    print(f"Failed: {outcomes['total_runs'] - outcomes['converged']}")
    print("\nOutcome breakdown:")
    for outcome, count in outcomes["outcomes"].items():
        print(f"  {outcome}: {count}")

    # Token usage
    print(f"\n{'Token Usage':—^60}")
    tokens = analysis["token_usage"]
    print(f"  Median:  {tokens['median']:,}")
    print(f"  Mean:    {tokens['mean']:,}")
    print(f"  p90:     {tokens['p90']:,}")
    print(f"  p99:     {tokens['p99']:,}")
    print(f"  Range:   {tokens['min']:,} - {tokens['max']:,}")

    # Cost
    print(f"\n{'Cost Distribution':—^60}")
    cost = analysis["cost"]
    print(f"  Median:  ${cost['median']:.2f}")
    print(f"  Mean:    ${cost['mean']:.2f}")
    print(f"  p90:     ${cost['p90']:.2f}")
    print(f"  p99:     ${cost['p99']:.2f}")
    print(f"  Total:   ${cost['total']:.2f}")

    # Steps
    print(f"\n{'Step Count':—^60}")
    steps = analysis["steps"]
    print(f"  Median:  {steps['median']}")
    print(f"  Mean:    {steps['mean']:.1f}")
    print(f"  p90:     {steps['p90']}")
    print(f"  Range:   {steps['min']} - {steps['max']}")

    # Tool usage
    print(f"\n{'Tool Usage':—^60}")
    tools = analysis["tool_usage"]
    if tools:
        for tool, stats in sorted(
            tools.items(), key=lambda x: x[1]["usage_rate"], reverse=True
        ):
            print(f"  {tool}:")
            print(f"    Usage rate: {stats['usage_rate']}%")
            print(f"    Success correlation: {stats['success_rate']}%")
    else:
        print("  No tool usage data")

    # Verifiers
    print(f"\n{'Verifier Analysis':—^60}")
    verifiers = analysis["verifiers"]
    if verifiers:
        for name, stats in verifiers.items():
            quality_marker = "✓" if stats["signal_quality"] == "GOOD" else "⚠"
            print(f"  {quality_marker} {name}:")
            print(
                f"    Pass rate: {stats['pass_rate']}% ({stats['pass']}/{stats['total']})"
            )
            print(f"    Signal quality: {stats['signal_quality']}")
    else:
        print("  No verifier data")

    print(f"\n{'='*60}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze all trajectories for a portlang field"
    )
    parser.add_argument("field_name", help="Name of the field to analyze")
    parser.add_argument(
        "--format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )
    parser.add_argument("--output", help="Output file path (default: stdout)")

    args = parser.parse_args()

    # Load trajectories
    trajectories = load_trajectories(args.field_name)

    # Perform analysis
    analysis = {
        "field_name": args.field_name,
        "outcomes": analyze_outcomes(trajectories),
        "token_usage": analyze_token_usage(trajectories),
        "cost": analyze_cost(trajectories),
        "steps": analyze_steps(trajectories),
        "tool_usage": analyze_tool_usage(trajectories),
        "verifiers": analyze_verifiers(trajectories),
    }

    # Output results
    if args.format == "json":
        output = json.dumps(analysis, indent=2)
        if args.output:
            with open(args.output, "w") as f:
                f.write(output)
            print(f"Analysis written to {args.output}")
        else:
            print(output)
    else:
        if args.output:
            print("Warning: --output only works with --format json", file=sys.stderr)
        print_text_report(analysis, args.field_name)


if __name__ == "__main__":
    main()
