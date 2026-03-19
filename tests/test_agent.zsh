#!/usr/bin/env zsh
# test_agent.zsh — Tests for AI agent integration: context, claude-md, workspace gen

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../lib/_wf_toml.zsh"
source "$SCRIPT_DIR/../lib/_wf_core.zsh"
source "$SCRIPT_DIR/../lib/_wf_git.zsh"
source "$SCRIPT_DIR/../lib/_wf_forest.zsh"
source "$SCRIPT_DIR/../lib/_wf_agent.zsh"

# ── Setup: temp forest with repos ──

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

FOREST="$TMPDIR_BASE/ctx-forest"
mkdir -p "$FOREST"

# Create repos with commits and CLAUDE.md
for name in api web; do
  mkdir -p "$FOREST/$name"
  (
    cd "$FOREST/$name"
    git init -q
    echo "# $name service" > README.md
    git add README.md
    git commit -m "init $name" -q
    echo "second change" >> README.md
    git add README.md
    git commit -m "update $name readme" -q
  )
done

# Add CLAUDE.md to api repo
cat > "$FOREST/api/CLAUDE.md" <<'CLAUDEEOF'
# CLAUDE.md

## Project Overview
API service for the platform.

## Common Commands
- npm run dev
- npm test
CLAUDEEOF

# Create forest.toml
cat > "$FOREST/forest.toml" <<'EOF'
[forest]
name = "context-test"
description = "Testing context generation"

[repos.api]
path = "api"
role = "backend"

[repos.web]
path = "web"
role = "frontend"
EOF

mkdir -p "$FOREST/.wf"
cd "$FOREST"

# ── Tests: wf context ──

echo "Test: wf context generates .wf/context.md..."
_wf_cmd_context 2>&1 >/dev/null
[[ -f "$FOREST/.wf/context.md" ]] || { echo "FAIL: context.md not created"; exit 1; }
echo "  PASS"

echo "Test: context.md contains forest name..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"context-test"* ]] || { echo "FAIL: missing forest name"; exit 1; }
echo "  PASS"

echo "Test: context.md contains timestamp..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"Generated:"* ]] || { echo "FAIL: missing timestamp"; exit 1; }
echo "  PASS"

echo "Test: context.md contains branch alignment section..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"Branch Alignment"* ]] || { echo "FAIL: missing branch alignment"; exit 1; }
echo "  PASS"

echo "Test: context.md shows aligned branches when all on same branch..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"All repos on:"* ]] || { echo "FAIL: should show aligned, got misaligned"; exit 1; }
echo "  PASS"

echo "Test: context.md detects misaligned branches..."
DEFAULT_BRANCH=$(cd "$FOREST/api" && git branch --show-current)
(cd "$FOREST/api" && git checkout -b feat/new -q)
_wf_cmd_context 2>&1 >/dev/null
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"WARNING"* ]] || { echo "FAIL: should warn about different branches"; exit 1; }
[[ "$content" == *"api:"* ]] || { echo "FAIL: should list api branch"; exit 1; }
[[ "$content" == *"web:"* ]] || { echo "FAIL: should list web branch"; exit 1; }
(cd "$FOREST/api" && git checkout "$DEFAULT_BRANCH" -q)
echo "  PASS"

echo "Test: context.md contains repo status sections..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"### api"* ]] || { echo "FAIL: missing api section"; exit 1; }
[[ "$content" == *"### web"* ]] || { echo "FAIL: missing web section"; exit 1; }
echo "  PASS"

echo "Test: context.md shows clean/dirty status..."
_wf_cmd_context 2>&1 >/dev/null
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"**Status:** clean"* ]] || { echo "FAIL: should show clean status"; exit 1; }
echo "  PASS"

echo "Test: context.md shows dirty status and changes..."
echo "dirty" >> "$FOREST/api/README.md"
_wf_cmd_context 2>&1 >/dev/null
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"**Status:** dirty"* ]] || { echo "FAIL: should show dirty status"; exit 1; }
[[ "$content" == *"**Changes:**"* ]] || { echo "FAIL: should show changes section"; exit 1; }
(cd "$FOREST/api" && git checkout -- README.md)
echo "  PASS"

echo "Test: context.md contains recent commits..."
content=$(cat "$FOREST/.wf/context.md")
[[ "$content" == *"Recent commits"* ]] || { echo "FAIL: missing recent commits"; exit 1; }
[[ "$content" == *"update api readme"* ]] || { echo "FAIL: missing commit message"; exit 1; }
echo "  PASS"

# ── Tests: wf claude-md ──

echo "Test: wf claude-md generates CLAUDE.md..."
_wf_cmd_claude_md 2>&1 >/dev/null
[[ -f "$FOREST/CLAUDE.md" ]] || { echo "FAIL: CLAUDE.md not created"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md contains forest name..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"context-test"* ]] || { echo "FAIL: missing forest name"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md contains description..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"Testing context generation"* ]] || { echo "FAIL: missing description"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md contains multi-repo note..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"multi-repo workspace"* ]] || { echo "FAIL: missing multi-repo note"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md lists repo sections..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"### api"* ]] || { echo "FAIL: missing api section"; exit 1; }
[[ "$content" == *"### web"* ]] || { echo "FAIL: missing web section"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md shows repo roles..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"backend"* ]] || { echo "FAIL: missing backend role"; exit 1; }
[[ "$content" == *"frontend"* ]] || { echo "FAIL: missing frontend role"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md includes repo CLAUDE.md excerpt..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"API service for the platform"* ]] || { echo "FAIL: missing api CLAUDE.md content"; exit 1; }
echo "  PASS"

echo "Test: CLAUDE.md contains cross-repo rules..."
content=$(cat "$FOREST/CLAUDE.md")
[[ "$content" == *"Cross-Repo Rules"* ]] || { echo "FAIL: missing cross-repo rules"; exit 1; }
[[ "$content" == *"API changes"* ]] || { echo "FAIL: missing API change rule"; exit 1; }
echo "  PASS"

# ── Tests: workspace generation ──

echo "Test: _wf_generate_workspace creates .code-workspace file..."
_wf_generate_workspace 2>&1 >/dev/null
[[ -f "$FOREST/.wf/forest.code-workspace" ]] || { echo "FAIL: workspace file not created"; exit 1; }
echo "  PASS"

echo "Test: workspace file contains folder entries..."
content=$(cat "$FOREST/.wf/forest.code-workspace")
[[ "$content" == *'"folders"'* ]] || { echo "FAIL: missing folders key"; exit 1; }
[[ "$content" == *'"name": "api"'* ]] || { echo "FAIL: missing api folder"; exit 1; }
[[ "$content" == *'"name": "web"'* ]] || { echo "FAIL: missing web folder"; exit 1; }
echo "  PASS"

echo "Test: workspace file has path entries..."
content=$(cat "$FOREST/.wf/forest.code-workspace")
[[ "$content" == *'"path":'* ]] || { echo "FAIL: missing path entries"; exit 1; }
echo "  PASS"

# ── Tests: cursorrules generation ──

echo "Test: _wf_generate_cursorrules creates .cursorrules..."
_wf_generate_cursorrules 2>&1 >/dev/null
[[ -f "$FOREST/.cursorrules" ]] || { echo "FAIL: .cursorrules not created"; exit 1; }
echo "  PASS"

echo "Test: .cursorrules contains forest name..."
content=$(cat "$FOREST/.cursorrules")
[[ "$content" == *"context-test"* ]] || { echo "FAIL: missing forest name"; exit 1; }
echo "  PASS"

echo "Test: .cursorrules lists repos with roles..."
content=$(cat "$FOREST/.cursorrules")
[[ "$content" == *"api/"* ]] || { echo "FAIL: missing api"; exit 1; }
[[ "$content" == *"web/"* ]] || { echo "FAIL: missing web"; exit 1; }
[[ "$content" == *"backend"* ]] || { echo "FAIL: missing backend role"; exit 1; }
echo "  PASS"

echo "Test: .cursorrules contains consistency rules..."
content=$(cat "$FOREST/.cursorrules")
[[ "$content" == *"API contracts"* ]] || { echo "FAIL: missing API contract rule"; exit 1; }
echo "  PASS"

# ── Tests: wf agent (dry-run — don't actually launch) ──

echo "Test: wf agent with unknown type fails..."
output=$(_wf_cmd_agent unknown 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"Unknown agent type"* ]] || { echo "FAIL: expected error, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf open with unknown editor fails..."
output=$(_wf_cmd_open unknown 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"Unknown editor"* ]] || { echo "FAIL: expected error, got: $output"; exit 1; }
echo "  PASS"

# ── Tests: context without manifest (fallback) ──

echo "Test: wf context works without forest.toml..."
NOTOML="$TMPDIR_BASE/no-toml-ctx"
mkdir -p "$NOTOML/svc"
(cd "$NOTOML/svc" && git init -q && git commit --allow-empty -m "init" -q)
mkdir -p "$NOTOML/.wf"
cd "$NOTOML"
_wf_cmd_context 2>&1 >/dev/null
[[ -f "$NOTOML/.wf/context.md" ]] || { echo "FAIL: context.md not created without toml"; exit 1; }
content=$(cat "$NOTOML/.wf/context.md")
[[ "$content" == *"### svc"* ]] || { echo "FAIL: should find svc repo"; exit 1; }
cd "$FOREST"
echo "  PASS"

echo ""
echo "All agent integration tests passed!"
