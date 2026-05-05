#!/usr/bin/env bash
# Validate workflow tooling configuration against the actual project.
# Catches: phantom Sentrux paths, wrong commands, 2>/dev/null abuse,
# dead stack branches, wrong baseBranch, missing tools.
#
# Usage: ./scripts/validate-workflow.sh
#   --fix      Auto-fix where possible (Sentrux paths, Archon baseBranch)
#   --verbose  Show all checks including passing ones
#   --ci       Exit code 1 on any failure (for CI)
#
# Port this into agent-workflow-template/setup.sh as the final step.

set -euo pipefail

BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

FIX=0
VERBOSE=0
CI=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    --verbose) VERBOSE=1 ;;
    --ci) CI=1 ;;
  esac
done

PASS="${GREEN}\xE2\x9C\x93${RESET}"
FAIL="${RED}\xE2\x9C\x97${RESET}"
WARN="${YELLOW}!${RESET}"

total_checks=0
failed_checks=0
warn_checks=0
errors=()

pass() { if [ "$VERBOSE" -eq 1 ]; then printf "  $PASS  %s\n" "$1"; fi; total_checks=$((total_checks + 1)); }
fail() { printf "  $FAIL  %s\n" "$1"; errors+=("$1"); total_checks=$((total_checks + 1)); failed_checks=$((failed_checks + 1)); }
warn() { printf "  $WARN  %s\n" "$1"; total_checks=$((total_checks + 1)); warn_checks=$((warn_checks + 1)); }

detect_stack() {
    if [ -f "Package.swift" ]; then echo "swift"
    elif ls *.xcodeproj *.xcworkspace 2>/dev/null | grep -q .; then echo "swift"
    elif [ -f "Cargo.toml" ]; then echo "rust"
    elif [ -f "pubspec.yaml" ]; then echo "flutter"
    elif [ -f "package.json" ]; then echo "node"
    elif [ -f "pyproject.toml" ] || [ -f "requirements.txt" ]; then echo "python"
    else echo "unknown"; fi
}

STACK=$(detect_stack)

printf "\n${BOLD}Workflow Validation${RESET}  ${DIM}stack: %s${RESET}\n\n" "$STACK"

# ──────────────────────────────────────────────
# 1. Sentrux — layer paths exist on disk
# ──────────────────────────────────────────────
if [ -f ".sentrux/rules.toml" ]; then
    printf "${BOLD}Sentrux${RESET}\n"

    # Collect all paths from [[layers]] sections (value after "paths =")
    current_layer=""
    while IFS= read -r line; do
        if [[ "$line" =~ name\ =\ \"(.+)\" ]]; then
            current_layer="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ paths\ =\ \[(.+)\] ]]; then
            paths_raw="${BASH_REMATCH[1]}"
            while IFS=',' read -ra path_items; do
                for item in "${path_items[@]}"; do
                    item=$(echo "$item" | xargs | sed 's/^"//;s/"$//')
                    # Check if glob matches any real files or directory
                    # Remove trailing glob to find base path
                    clean=$(echo "$item" | sed 's|/\*\*/\?\*\.\w*$||;s|/\*$||')
                    if [ -z "$clean" ]; then clean="$item"; fi
                    hit_count=$(find . -path "./$item" 2>/dev/null | head -3 | wc -l)
                    if [ "$hit_count" -gt 0 ] || [ -e "$clean" ]; then
                        pass "  layer \"$current_layer\": $item exists"
                    else
                        fail "  layer \"$current_layer\": $item — path not found on disk"
                    fi
                done
            done <<< "$paths_raw"
        fi
    done < ".sentrux/rules.toml"
else
    warn "  no .sentrux/rules.toml found"
fi
echo ""

# ──────────────────────────────────────────────
# 2. Git hooks — no 2>/dev/null abuse, valid syntax, stack matching
# ──────────────────────────────────────────────
printf "${BOLD}Git Hooks${RESET}\n"

for hook in ".githooks/pre-commit" ".githooks/pre-push" ".githooks/post-commit" ".githooks/commit-msg"; do
    [ ! -f "$hook" ] && continue

    # Check bash syntax
    if bash -n "$hook" 2>/dev/null; then
        pass "  $hook: valid syntax"
    else
        fail "  $hook: syntax error"
        bash -n "$hook" 2>&1
    fi

    # Count 2>/dev/null in check commands (not existence checks)
    null_count=$(grep -c '2>/dev/null' "$hook" 2>/dev/null || true)
    if [ "$null_count" -gt 5 ] 2>/dev/null; then
        warn "  $hook: $null_count instances of 2>/dev/null — may hide failures"
    else
        pass "  $hook: $null_count 2>/dev/null instances (acceptable)"
    fi

    # Check for || true swallowing on non-existence checks
    swallow_count=$(grep -c '|| true' "$hook" 2>/dev/null || true)
    if [ "$swallow_count" -gt 3 ] 2>/dev/null; then
        warn "  $hook: $swallow_count '|| true' swallow patterns"
    fi

    # Hook-specific validation
    case "$hook" in
        ".githooks/pre-commit"|".githooks/pre-push")
            # Check that dead code branches don't exist
            for other_stack in "bun run" "cargo check" "flutter analyze" "npm test"; do
                if grep -q "$other_stack" "$hook" 2>/dev/null; then
                    case "$STACK" in
                        swift) warn "  $hook: contains '$other_stack' — dead code for Swift project" ;;
                    esac
                fi
            done
            ;;
    esac
done

# Verify hooks are active
HOOKS_PATH=$(git config core.hooksPath 2>/dev/null || echo "")
if [ "$HOOKS_PATH" = ".githooks" ]; then
    pass "  git hooks active (core.hooksPath = .githooks)"
else
    fail "  git hooks not active — run: git config core.hooksPath .githooks"
fi
echo ""

# ──────────────────────────────────────────────
# 3. Stack tools — required tools installed
# ──────────────────────────────────────────────
printf "${BOLD}Tools${RESET}\n"

case "$STACK" in
    swift)
        for tool in swiftformat; do
            if command -v "$tool" &>/dev/null; then
                pass "  $tool: installed ($($tool --version 2>/dev/null | head -1))"
            else
                warn "  $tool: not found — install: brew install $tool"
            fi
        done
        if command -v swiftlint &>/dev/null; then
            pass "  swiftlint: installed ($(swiftlint version 2>/dev/null))"
        else
            warn "  swiftlint: not found — install: brew install swiftlint"
        fi
        if command -v gitleaks &>/dev/null; then
            pass "  gitleaks: installed"
        else
            warn "  gitleaks: not found — install: brew install gitleaks"
        fi
        if command -v sentrux &>/dev/null; then
            pass "  sentrux: installed"
        else
            warn "  sentrux: not found"
        fi
        ;;
    node)
        for tool in node npm; do
            if command -v "$tool" &>/dev/null; then
                pass "  $tool: installed"
            else
                warn "  $tool: not found"
            fi
        done
        ;;
    rust)
        for tool in rustc cargo; do
            if command -v "$tool" &>/dev/null; then
                pass "  $tool: installed"
            else
                warn "  $tool: not found"
            fi
        done
        ;;
    flutter)
        if command -v flutter &>/dev/null; then
            pass "  flutter: installed"
        else
            warn "  flutter: not found"
        fi
        ;;
    python)
        for tool in python3 ruff; do
            if command -v "$tool" &>/dev/null; then
                pass "  $tool: installed"
            else
                warn "  $tool: not found"
            fi
        done
        ;;
esac
echo ""

# ──────────────────────────────────────────────
# 4. Archon — baseBranch exists
# ──────────────────────────────────────────────
if [ -f ".archon/config.yaml" ]; then
    printf "${BOLD}Archon${RESET}\n"

    BASE_BRANCH=$(grep 'baseBranch:' .archon/config.yaml | awk '{print $2}')
    if [ -n "$BASE_BRANCH" ]; then
        if git show-ref --verify --quiet "refs/heads/$BASE_BRANCH" 2>/dev/null; then
            pass "  baseBranch: $BASE_BRANCH exists"
        else
            fail "  baseBranch: $BASE_BRANCH — branch not found"
            if [ "$FIX" -eq 1 ]; then
                # Try main or master
                for candidate in main master develop; do
                    if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
                        sed -i '' "s/baseBranch: $BASE_BRANCH/baseBranch: $candidate/" .archon/config.yaml
                        echo "         fixed -> baseBranch: $candidate"
                        break
                    fi
                done
            fi
        fi
    fi

    # Check workflows are valid YAML
    for wf in .archon/workflows/*.yaml; do
        [ ! -f "$wf" ] && continue
        if python3 -c "import yaml; yaml.safe_load(open('$wf'))" 2>/dev/null || yq eval '.' "$wf" >/dev/null 2>&1; then
            pass "  workflow $(basename "$wf"): valid YAML"
        else
            fail "  workflow $(basename "$wf"): invalid YAML"
        fi
    done
fi
echo ""

# ──────────────────────────────────────────────
# 5. Graphify — config valid
# ──────────────────────────────────────────────
if [ -f ".graphify/config.yaml" ]; then
    printf "${BOLD}Graphify${RESET}\n"

    # Check include patterns match actual files (only lines under include: key)
    MISSING=0
    in_include=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^include: ]]; then
            in_include=1
            continue
        elif [[ "$line" =~ ^[a-z] ]] && [ "$in_include" -eq 1 ]; then
            in_include=0
        fi
        [ "$in_include" -eq 0 ] && continue
        pattern=$(echo "$line" | sed 's/^[[:space:]]*- //' | xargs)
        [ -z "$pattern" ] && continue
        match_count=$(find . -path "./$pattern" 2>/dev/null | head -5 | wc -l)
        if [ "$match_count" -eq 0 ]; then
            fail "  include '$pattern' matches no files"
            MISSING=1
        fi
    done < ".graphify/config.yaml"
    if [ "$MISSING" -eq 0 ]; then
        pass "  include patterns match project files"
    fi
fi
echo ""

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
printf "${BOLD}Results${RESET}  ${GREEN}%d passed${RESET}  ", "$((total_checks - failed_checks - warn_checks))"
[ "$failed_checks" -gt 0 ] && printf "${RED}%d failed${RESET}  " "$failed_checks"
[ "$warn_checks" -gt 0 ] && printf "${YELLOW}%d warnings${RESET}  " "$warn_checks"
printf "${DIM}(%d total)${RESET}\n" "$total_checks"

if [ "$failed_checks" -gt 0 ]; then
    echo ""
    printf "${RED}${BOLD}Issues to fix:${RESET}\n"
    for e in "${errors[@]}"; do
        printf "  ${RED}\xE2\x80\xA2${RESET} %s\n" "$e"
    done
    echo ""
    if [ "$CI" -eq 1 ]; then
        exit 1
    fi
fi
