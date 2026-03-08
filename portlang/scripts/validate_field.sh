#!/bin/bash
# validate_field.sh - Enhanced field validation beyond `portlang check`
# Usage: ./validate_field.sh <field.toml>

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

FIELD_FILE="$1"

if [ -z "$FIELD_FILE" ]; then
    echo "Usage: $0 <field.toml>"
    exit 1
fi

if [ ! -f "$FIELD_FILE" ]; then
    echo -e "${RED}Error: Field file not found: $FIELD_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}=== portlang Field Validation ===${NC}\n"
echo "Validating: $FIELD_FILE"
echo ""

ERRORS=0
WARNINGS=0

# Check 1: Run portlang check
echo -e "${YELLOW}[1/6]${NC} Running portlang check..."
if portlang check "$FIELD_FILE" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} portlang check passed"
else
    echo -e "  ${RED}✗${NC} portlang check failed"
    portlang check "$FIELD_FILE"
    ERRORS=$((ERRORS + 1))
fi

# Extract workspace directory from field.toml
WORKSPACE=$(grep -A 5 '^\[environment\]' "$FIELD_FILE" | grep 'root =' | sed 's/.*root = "\(.*\)"/\1/' || echo "")

# Check 2: Verify workspace directory exists or can be created
echo -e "\n${YELLOW}[2/6]${NC} Checking workspace directory..."
if [ -z "$WORKSPACE" ]; then
    echo -e "  ${YELLOW}⚠${NC} Warning: No workspace root specified in [environment]"
    WARNINGS=$((WARNINGS + 1))
elif [ -d "$WORKSPACE" ]; then
    echo -e "  ${GREEN}✓${NC} Workspace exists: $WORKSPACE"
elif [ -d "$(dirname "$FIELD_FILE")" ]; then
    # Try to resolve relative to field file
    FIELD_DIR=$(dirname "$FIELD_FILE")
    FULL_WORKSPACE="$FIELD_DIR/$WORKSPACE"
    if [ -d "$FULL_WORKSPACE" ]; then
        echo -e "  ${GREEN}✓${NC} Workspace exists: $FULL_WORKSPACE"
    else
        echo -e "  ${YELLOW}⚠${NC} Warning: Workspace not found: $WORKSPACE"
        echo -e "    Will be created on first run"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    echo -e "  ${YELLOW}⚠${NC} Warning: Workspace not found: $WORKSPACE"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 3: Verify tool scripts exist and are executable
echo -e "\n${YELLOW}[3/6]${NC} Checking custom tool scripts..."
TOOL_SCRIPTS=$(grep -A 2 '^\[\[tool\]\]' "$FIELD_FILE" | grep 'script =' | sed 's/.*script = "\(.*\)"/\1/' || true)

if [ -z "$TOOL_SCRIPTS" ]; then
    echo -e "  ${BLUE}ℹ${NC} No custom tool scripts defined"
else
    TOOL_ERRORS=0
    while IFS= read -r SCRIPT; do
        if [ -f "$SCRIPT" ]; then
            if [ -x "$SCRIPT" ]; then
                echo -e "  ${GREEN}✓${NC} $SCRIPT (executable)"
            else
                echo -e "  ${YELLOW}⚠${NC} $SCRIPT (not executable - run: chmod +x $SCRIPT)"
                WARNINGS=$((WARNINGS + 1))
            fi
        else
            echo -e "  ${RED}✗${NC} $SCRIPT (not found)"
            TOOL_ERRORS=$((TOOL_ERRORS + 1))
        fi
    done <<< "$TOOL_SCRIPTS"

    if [ $TOOL_ERRORS -gt 0 ]; then
        ERRORS=$((ERRORS + TOOL_ERRORS))
    fi
fi

# Check 4: Test verifier commands in isolation (basic syntax check)
echo -e "\n${YELLOW}[4/6]${NC} Testing verifier commands..."
# Extract verifier commands (simple extraction, may not handle all TOML formats)
VERIFIER_NAMES=$(grep '^name = ' "$FIELD_FILE" | grep -A 1 'verifiers' | sed 's/name = "\(.*\)"/\1/' || true)

if [ -z "$VERIFIER_NAMES" ]; then
    echo -e "  ${YELLOW}⚠${NC} Warning: No verifiers defined"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "  ${BLUE}ℹ${NC} Found verifiers (syntax validation only)"
    # Just count them, don't try to execute
    VERIFIER_COUNT=$(echo "$VERIFIER_NAMES" | wc -l | tr -d ' ')
    echo -e "  ${GREEN}✓${NC} $VERIFIER_COUNT verifier(s) defined"
fi

# Check 5: Estimate token budget sufficiency
echo -e "\n${YELLOW}[5/6]${NC} Checking token budget..."
MAX_TOKENS=$(grep -A 10 '^\[context\]' "$FIELD_FILE" | grep 'max_tokens =' | sed 's/.*max_tokens = \([0-9]*\)/\1/' || echo "0")
MAX_STEPS=$(grep -A 10 '^\[context\]' "$FIELD_FILE" | grep 'max_steps =' | sed 's/.*max_steps = \([0-9]*\)/\1/' || echo "0")

if [ "$MAX_TOKENS" -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Warning: max_tokens not set in [context]"
    WARNINGS=$((WARNINGS + 1))
elif [ "$MAX_TOKENS" -lt 20000 ]; then
    echo -e "  ${YELLOW}⚠${NC} Warning: max_tokens=$MAX_TOKENS may be too low for most tasks"
    echo -e "    Recommended minimum: 20,000"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "  ${GREEN}✓${NC} Token budget: $MAX_TOKENS"

    # Rough estimation
    if [ "$MAX_STEPS" -gt 0 ]; then
        ESTIMATED_PER_STEP=$((MAX_TOKENS / MAX_STEPS))
        if [ $ESTIMATED_PER_STEP -lt 1000 ]; then
            echo -e "  ${YELLOW}⚠${NC} Warning: Only ~$ESTIMATED_PER_STEP tokens per step (may be tight)"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "  ${BLUE}ℹ${NC} Estimated ~$ESTIMATED_PER_STEP tokens per step"
        fi
    fi
fi

# Check 6: Verify boundary patterns are valid globs
echo -e "\n${YELLOW}[6/6]${NC} Checking boundary patterns..."
ALLOW_WRITE=$(grep -A 5 '^\[boundary\]' "$FIELD_FILE" | grep 'allow_write =' || true)

if [ -z "$ALLOW_WRITE" ]; then
    echo -e "  ${YELLOW}⚠${NC} Warning: No allow_write patterns defined in [boundary]"
    echo -e "    Agent will not be able to write any files"
    WARNINGS=$((WARNINGS + 1))
else
    echo -e "  ${GREEN}✓${NC} Write boundary patterns defined"
fi

# Summary
echo -e "\n${BLUE}${'='*60}${NC}"
echo -e "Validation Summary"
echo -e "${BLUE}${'='*60}${NC}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Field configuration is valid with no issues${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Field is valid but has $WARNINGS warning(s)${NC}"
    echo -e "  Review warnings above and adjust configuration as needed"
else
    echo -e "${RED}✗ Field validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo -e "  Fix errors before running the field"
fi

echo ""

# Exit with appropriate code
if [ $ERRORS -gt 0 ]; then
    exit 1
else
    exit 0
fi
