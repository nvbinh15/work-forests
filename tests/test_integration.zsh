#!/usr/bin/env zsh
# test_integration.zsh — End-to-end integration tests using the plugin entry point

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../work-forest.plugin.zsh"

# ── Setup: create a realistic forest ──

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

FOREST="$TMPDIR_BASE/e2e-forest"
mkdir -p "$FOREST"

# Create backend repo with commits and a CLAUDE.md
mkdir -p "$FOREST/be"
(
  cd "$FOREST/be"
  git init -q
  echo "# Backend" > README.md
  git add README.md
  git commit -m "init backend" -q
  cat > CLAUDE.md <<'INNER'
# CLAUDE.md
Backend service. Node.js + Express.
## Commands
- npm run dev
INNER
  git add CLAUDE.md
  git commit -m "add CLAUDE.md" -q
)

# Create frontend repo
mkdir -p "$FOREST/fe"
(
  cd "$FOREST/fe"
  git init -q
  echo "# Frontend" > README.md
  git add README.md
  git commit -m "init frontend" -q
)

cd "$FOREST"

# ── Test: full lifecycle ──

echo "Test: E2E — init, status, list, context, claude-md, checkout, add, remove..."

# 1. Init
output=$(wf init --name e2e-test 2>&1)
[[ -f "$FOREST/forest.toml" ]] || { echo "FAIL: init — no forest.toml"; exit 1; }
[[ "$output" == *"2 repo(s)"* ]] || { echo "FAIL: init — wrong count, got: $output"; exit 1; }
echo "  init: PASS"

# 2. Status
output=$(wf status 2>&1)
[[ "$output" == *"be"* ]] || { echo "FAIL: status — missing be"; exit 1; }
[[ "$output" == *"fe"* ]] || { echo "FAIL: status — missing fe"; exit 1; }
[[ "$output" == *"clean"* ]] || { echo "FAIL: status — should be clean"; exit 1; }
echo "  status: PASS"

# 3. List
output=$(wf list 2>&1)
[[ "$output" == *"e2e-test"* ]] || { echo "FAIL: list — missing forest name"; exit 1; }
[[ "$output" == *"backend"* ]] || { echo "FAIL: list — missing role"; exit 1; }
echo "  list: PASS"

# 4. List JSON
output=$(wf list --json 2>&1)
[[ "$output" == "["* ]] || { echo "FAIL: list --json — invalid JSON start"; exit 1; }
echo "  list --json: PASS"

# 5. Checkout -b across all repos
wf checkout -b feat/e2e-test 2>&1 >/dev/null
branch_be=$(cd "$FOREST/be" && git branch --show-current)
branch_fe=$(cd "$FOREST/fe" && git branch --show-current)
[[ "$branch_be" = "feat/e2e-test" ]] || { echo "FAIL: checkout — be on '$branch_be'"; exit 1; }
[[ "$branch_fe" = "feat/e2e-test" ]] || { echo "FAIL: checkout — fe on '$branch_fe'"; exit 1; }
echo "  checkout -b: PASS"

# 6. Context
wf context 2>&1 >/dev/null
[[ -f "$FOREST/.wf/context.md" ]] || { echo "FAIL: context — file not created"; exit 1; }
ctx=$(cat "$FOREST/.wf/context.md")
[[ "$ctx" == *"All repos on:"* ]] || { echo "FAIL: context — should be aligned"; exit 1; }
[[ "$ctx" == *"feat/e2e-test"* ]] || { echo "FAIL: context — wrong branch in output"; exit 1; }
echo "  context: PASS"

# 7. Claude-md
wf claude-md 2>&1 >/dev/null
[[ -f "$FOREST/CLAUDE.md" ]] || { echo "FAIL: claude-md — file not created"; exit 1; }
claude=$(cat "$FOREST/CLAUDE.md")
[[ "$claude" == *"Backend service"* ]] || { echo "FAIL: claude-md — missing repo CLAUDE.md excerpt"; exit 1; }
[[ "$claude" == *"### fe"* ]] || { echo "FAIL: claude-md — missing fe section"; exit 1; }
echo "  claude-md: PASS"

# 8. Log
output=$(wf log 2 2>&1)
[[ "$output" == *"init backend"* ]] || { echo "FAIL: log — missing commit"; exit 1; }
echo "  log: PASS"

# 9. Exec
output=$(wf exec 'echo hello' 2>&1)
hello_count=$(echo "$output" | grep -c "hello" || true)
[[ "$hello_count" -eq 2 ]] || { echo "FAIL: exec — expected 2 hellos, got $hello_count"; exit 1; }
echo "  exec: PASS"

# 10. Add a new repo
mkdir -p "$FOREST/infra"
(cd "$FOREST/infra" && git init -q && git commit --allow-empty -m "init infra" -q)
wf add infra --role infra 2>&1 >/dev/null
repos=$(_wf_toml_repos "$FOREST/forest.toml")
[[ "$repos" == *"infra"* ]] || { echo "FAIL: add — infra not in manifest"; exit 1; }
echo "  add: PASS"

# 11. Verify new repo appears in status
output=$(wf status 2>&1)
[[ "$output" == *"infra"* ]] || { echo "FAIL: add — infra not in status"; exit 1; }
echo "  add shows in status: PASS"

# 12. Remove
wf remove infra 2>&1 >/dev/null
repos=$(_wf_toml_repos "$FOREST/forest.toml")
[[ "$repos" != *"infra"* ]] || { echo "FAIL: remove — infra still in manifest"; exit 1; }
[[ -d "$FOREST/infra" ]] || { echo "FAIL: remove — infra dir deleted"; exit 1; }
echo "  remove: PASS"

# 13. Status with --repo filter
output=$(wf status --repo be 2>&1)
[[ "$output" == *"be"* ]] || { echo "FAIL: status --repo — missing be"; exit 1; }
[[ "$output" != *"── fe ──"* ]] || { echo "FAIL: status --repo — fe should not appear"; exit 1; }
echo "  status --repo: PASS"

# 14. Diff with dirty repo
echo "changed" >> "$FOREST/be/README.md"
output=$(wf diff 2>&1)
[[ "$output" == *"README.md"* ]] || { echo "FAIL: diff — should show changed file"; exit 1; }
(cd "$FOREST/be" && git checkout -- README.md)
echo "  diff: PASS"

# 15. Stash push/pop (|| true because repos with nothing to stash return non-zero on pop)
echo "stash this" >> "$FOREST/be/README.md"
wf stash push 2>&1 >/dev/null || true
[[ "$(cat "$FOREST/be/README.md")" != *"stash this"* ]] || { echo "FAIL: stash push — change not stashed"; exit 1; }
wf stash pop 2>&1 >/dev/null || true
[[ "$(cat "$FOREST/be/README.md")" == *"stash this"* ]] || { echo "FAIL: stash pop — change not restored"; exit 1; }
(cd "$FOREST/be" && git checkout -- README.md)
echo "  stash push/pop: PASS"

# 16. Version
output=$(wf version 2>&1)
[[ "$output" == *"work-forest v"* ]] || { echo "FAIL: version — unexpected output: $output"; exit 1; }
echo "  version: PASS"

# 17. Help
output=$(wf help 2>&1)
[[ "$output" == *"work-forest"* ]] || { echo "FAIL: help — missing tool name"; exit 1; }
[[ "$output" == *"FOREST MANAGEMENT"* ]] || { echo "FAIL: help — missing section"; exit 1; }
echo "  help: PASS"

# 18. Unknown command
output=$(wf nonexistent 2>&1) && { echo "FAIL: unknown cmd — should have failed"; exit 1; } || true
[[ "$output" == *"Unknown command"* ]] || { echo "FAIL: unknown cmd — wrong error: $output"; exit 1; }
echo "  unknown command: PASS"

# 19. Backward-compat aliases exist (check they're defined)
output=$(alias wfstatus 2>&1)
[[ "$output" == *"wf status"* ]] || { echo "FAIL: wfstatus alias not defined"; exit 1; }
output=$(alias wfpull 2>&1)
[[ "$output" == *"wf pull"* ]] || { echo "FAIL: wfpull alias not defined"; exit 1; }
echo "  backward-compat aliases: PASS"

# 20. Checkout back to default branch across all repos
DEFAULT_BRANCH=$(cd "$FOREST/be" && git log --format=%D -1 | sed 's/.*-> //' | sed 's|HEAD -> ||' || echo "main")
# Determine actual default branch from first commit
DEFAULT_BRANCH=$(cd "$FOREST/be" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
# We're currently on feat/e2e-test, so get the other branch
DEFAULT_BRANCH=$(cd "$FOREST/be" && git branch --list | grep -v feat | sed 's/[* ]//g' | head -1)
wf checkout "$DEFAULT_BRANCH" 2>&1 >/dev/null
branch_be=$(cd "$FOREST/be" && git branch --show-current)
branch_fe=$(cd "$FOREST/fe" && git branch --show-current)
[[ "$branch_be" = "$DEFAULT_BRANCH" ]] || { echo "FAIL: checkout default — be on '$branch_be'"; exit 1; }
[[ "$branch_fe" = "$DEFAULT_BRANCH" ]] || { echo "FAIL: checkout default — fe on '$branch_fe'"; exit 1; }
echo "  checkout default branch: PASS"

echo ""
echo "All integration tests passed!"
