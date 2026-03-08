# Port of Context Skills

AI agent skills for Port of Context tools.

## Available Skills

### portlang

portlang is the environment-first agent framework. Learn how to create field.toml configurations, define boundaries and verifiers, add custom tools, debug with trajectories, and optimize agent reliability.

**Install:**
```bash
npx skills add https://github.com/portofcontext/skills --skill portlang
```

**What you'll learn:**
- Creating and configuring field.toml files for agent tasks
- Defining boundaries and verifiers to control agent behavior
- Adding custom tools (shell, Python, or MCP servers)
- Debugging agent failures using trajectories
- Optimizing agent reliability with convergence testing
- Configuring Code Mode for token-efficient operations
- Structuring multi-layer verification patterns
- Analyzing agent behavior across multiple runs

**Documentation:** See [portlang/SKILL.md](portlang/SKILL.md) for complete skill guide.

**Reference materials:**
- [Verifier Patterns](portlang/reference/verifier_patterns.md) - 15+ real-world examples
- [Custom Tools Guide](portlang/reference/custom_tools.md) - Shell, Python, and MCP tools
- [Trajectory Analysis](portlang/reference/trajectory_analysis.md) - Advanced debugging techniques
- [Field Recipes](portlang/reference/field_recipes.md) - Complete field.toml examples

**Helper scripts:**
- `scripts/new_field.sh` - Interactive field template generator
- `scripts/validate_field.sh` - Enhanced field validation
- `scripts/analyze_trajectories.py` - Multi-trajectory analyzer

## About

portlang is an environment-first agent framework that treats agent behavior as search through a conditioned space. Unlike traditional agent frameworks that manage loops, portlang manages environments.

**Core principle:** Define the search space. The agent finds the path.

Learn more: https://github.com/portofcontext/portlang

