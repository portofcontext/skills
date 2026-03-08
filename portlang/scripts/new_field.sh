#!/bin/bash
# new_field.sh - Interactive field template generator
# Usage: ./new_field.sh [field-name]

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== portlang Field Generator ===${NC}\n"

# Get field name
if [ -z "$1" ]; then
    read -p "Field name: " FIELD_NAME
else
    FIELD_NAME="$1"
fi

# Validate field name
if [ -z "$FIELD_NAME" ]; then
    echo "Error: Field name cannot be empty"
    exit 1
fi

# Get goal/description
echo ""
read -p "Brief description: " DESCRIPTION

echo ""
echo "Enter the goal (end with Ctrl+D on a new line):"
GOAL=$(cat)

# Model selection
echo -e "\n${YELLOW}Select model:${NC}"
echo "1) anthropic/claude-sonnet-4.6 (recommended)"
echo "2) anthropic/claude-opus-4.5"
echo "3) Custom (enter manually)"
read -p "Choice [1]: " MODEL_CHOICE
MODEL_CHOICE=${MODEL_CHOICE:-1}

case $MODEL_CHOICE in
    1)
        MODEL="anthropic/claude-sonnet-4.6"
        ;;
    2)
        MODEL="anthropic/claude-opus-4.5"
        ;;
    3)
        read -p "Model name: " MODEL
        ;;
    *)
        MODEL="anthropic/claude-sonnet-4.6"
        ;;
esac

# Workspace path
read -p "Workspace path [./workspace]: " WORKSPACE
WORKSPACE=${WORKSPACE:-./workspace}

# Create directory structure
FIELD_DIR="${FIELD_NAME}"
mkdir -p "$FIELD_DIR"
mkdir -p "$FIELD_DIR/workspace"
mkdir -p "$FIELD_DIR/tools"

# Generate field.toml
cat > "$FIELD_DIR/field.toml" <<EOF
name = "$FIELD_NAME"
description = "$DESCRIPTION"

goal = """
$GOAL
"""

[model]
name = "$MODEL"
temperature = 1.0
max_tokens = 4000

[environment]
type = "local"
root = "$WORKSPACE"

[boundary]
allow_write = ["output.json"]  # Adjust as needed

[context]
max_tokens = 80000
max_cost = "\$1.00"
max_steps = 30

# Add verifiers below
[[verifiers]]
name = "output-exists"
command = "test -f output.json"
trigger = "on_stop"
description = "output.json must exist"
EOF

# Create README
cat > "$FIELD_DIR/README.md" <<EOF
# $FIELD_NAME

$DESCRIPTION

## Goal

$GOAL

## Usage

\`\`\`bash
# Validate configuration
portlang check field.toml

# Run once
portlang run field.toml

# Test reliability (10 runs)
portlang converge field.toml -n 10

# View trajectories
portlang list

# Replay a specific run
portlang replay <trajectory-id>
\`\`\`

## Configuration

- Model: $MODEL
- Max tokens: 80,000
- Max cost: \$1.00
- Max steps: 30

## Next Steps

1. Edit \`field.toml\` to add verifiers and adjust boundaries
2. Create any custom tools in \`tools/\` directory
3. Run \`portlang check field.toml\` to validate
4. Run \`portlang run field.toml\` to execute
EOF

# Success message
echo -e "\n${GREEN}✓ Field created successfully!${NC}\n"
echo "Directory structure:"
echo "$FIELD_DIR/"
echo "├── field.toml       # Field configuration"
echo "├── README.md        # Documentation"
echo "├── workspace/       # Agent workspace"
echo "└── tools/           # Custom tools (if needed)"
echo ""
echo "Next steps:"
echo "1. cd $FIELD_DIR"
echo "2. Edit field.toml to customize verifiers and boundaries"
echo "3. portlang check field.toml"
echo "4. portlang run field.toml"
echo ""
echo -e "${YELLOW}Tip:${NC} See reference/field_recipes.md for complete examples"
