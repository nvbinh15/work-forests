#!/usr/bin/env zsh
# test_git.zsh — Tests for git operations across forest repos

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../lib/_wf_toml.zsh"
source "$SCRIPT_DIR/../lib/_wf_core.zsh"
source "$SCRIPT_DIR/../lib/_wf_git.zsh"

# ── Setup: create temp forest with two repos ──

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

FOREST="$TMPDIR_BASE/test-forest"
mkdir -p "$FOREST"

# Create two repos with some commits
for name in alpha beta; do
  mkdir -p "$FOREST/$name"
  (
    cd "$FOREST/$name"
    git init -q
    git commit --allow-empty -m "initial commit for $name" -q
    echo "line1" > file.txt
    git add file.txt
    git commit -m "add file.txt to $name" -q
  )
done

# Create forest.toml
cat > "$FOREST/forest.toml" <<'EOF'
[forest]
name = "test-git"

[repos.alpha]
path = "alpha"
role = "backend"

[repos.beta]
path = "beta"
role = "frontend"
EOF

cd "$FOREST"

# Detect default branch name (main or master depending on git config)
DEFAULT_BRANCH=$(cd "$FOREST/alpha" && git branch --show-current)

# ── Tests ──

echo "Test: wf status shows all repos..."
output=$(_wf_cmd_status 2>&1)
[[ "$output" == *"alpha"* ]] || { echo "FAIL: missing alpha"; exit 1; }
[[ "$output" == *"beta"* ]] || { echo "FAIL: missing beta"; exit 1; }
echo "  PASS"

echo "Test: wf status --repo filters to single repo..."
output=$(_wf_cmd_status --repo alpha 2>&1)
[[ "$output" == *"alpha"* ]] || { echo "FAIL: missing alpha"; exit 1; }
[[ "$output" != *"── beta ──"* ]] || { echo "FAIL: beta should not appear"; exit 1; }
echo "  PASS"

echo "Test: wf status --repo with nonexistent repo fails..."
output=$(_wf_cmd_status --repo nonexistent 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"not found"* ]] || { echo "FAIL: expected error message, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf checkout -b creates branch across repos..."
_wf_cmd_checkout -b test-branch 2>&1 >/dev/null
branch_a=$(cd "$FOREST/alpha" && git branch --show-current)
branch_b=$(cd "$FOREST/beta" && git branch --show-current)
[[ "$branch_a" = "test-branch" ]] || { echo "FAIL: alpha on '$branch_a'"; exit 1; }
[[ "$branch_b" = "test-branch" ]] || { echo "FAIL: beta on '$branch_b'"; exit 1; }
echo "  PASS"

echo "Test: wf checkout switches back to existing branch..."
_wf_cmd_checkout "$DEFAULT_BRANCH" 2>&1 >/dev/null
branch_a=$(cd "$FOREST/alpha" && git branch --show-current)
[[ "$branch_a" = "$DEFAULT_BRANCH" ]] || { echo "FAIL: alpha on '$branch_a', expected $DEFAULT_BRANCH"; exit 1; }
echo "  PASS"

echo "Test: wf checkout --repo targets single repo..."
_wf_cmd_checkout test-branch --repo alpha 2>&1 >/dev/null
branch_a=$(cd "$FOREST/alpha" && git branch --show-current)
branch_b=$(cd "$FOREST/beta" && git branch --show-current)
[[ "$branch_a" = "test-branch" ]] || { echo "FAIL: alpha on '$branch_a'"; exit 1; }
[[ "$branch_b" = "$DEFAULT_BRANCH" ]] || { echo "FAIL: beta should stay on $DEFAULT_BRANCH, got '$branch_b'"; exit 1; }
# switch back
_wf_cmd_checkout "$DEFAULT_BRANCH" --repo alpha 2>&1 >/dev/null
echo "  PASS"

echo "Test: wf checkout with no branch shows usage..."
output=$(_wf_cmd_checkout 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"Usage"* ]] || { echo "FAIL: expected usage, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf log shows commits..."
output=$(_wf_cmd_log 2>&1)
[[ "$output" == *"add file.txt"* ]] || { echo "FAIL: missing commit message"; exit 1; }
echo "  PASS"

echo "Test: wf log with custom count..."
output=$(_wf_cmd_log 1 2>&1)
# Should show only 1 commit per repo (the most recent)
alpha_section=$(echo "$output" | sed -n '/alpha/,/beta/p')
# Count lines with commit hashes (7+ hex chars)
count=$(echo "$alpha_section" | grep -cE '^[0-9a-f]{7}' || true)
[[ "$count" -le 1 ]] || { echo "FAIL: expected 1 commit, got $count"; exit 1; }
echo "  PASS"

echo "Test: wf log --repo filters..."
output=$(_wf_cmd_log --repo beta 2>&1)
[[ "$output" == *"beta"* ]] || { echo "FAIL: missing beta"; exit 1; }
[[ "$output" != *"── alpha ──"* ]] || { echo "FAIL: alpha should not appear"; exit 1; }
echo "  PASS"

echo "Test: wf diff on clean repos shows nothing..."
output=$(_wf_cmd_diff 2>&1)
# Diff output should have repo headers but no file changes
[[ "$output" == *"alpha"* ]] || { echo "FAIL: missing alpha header"; exit 1; }
echo "  PASS"

echo "Test: wf diff detects changes..."
echo "new content" >> "$FOREST/alpha/file.txt"
output=$(_wf_cmd_diff 2>&1)
[[ "$output" == *"file.txt"* ]] || { echo "FAIL: should show changed file"; exit 1; }
# Revert
(cd "$FOREST/alpha" && git checkout -- file.txt)
echo "  PASS"

echo "Test: wf stash saves and restores changes..."
echo "stash me" >> "$FOREST/alpha/file.txt"
_wf_cmd_stash push 2>&1 >/dev/null || true
# File should be reverted
content=$(cat "$FOREST/alpha/file.txt")
[[ "$content" = "line1" ]] || { echo "FAIL: stash push didn't revert, got: $content"; exit 1; }
# Pop (ignore errors from repos with no stash)
_wf_cmd_stash pop 2>&1 >/dev/null || true
content=$(cat "$FOREST/alpha/file.txt")
[[ "$content" == *"stash me"* ]] || { echo "FAIL: stash pop didn't restore"; exit 1; }
# Clean up
(cd "$FOREST/alpha" && git checkout -- file.txt)
echo "  PASS"

echo "Test: wf exec runs command in each repo..."
output=$(_wf_cmd_exec pwd 2>&1)
[[ "$output" == *"$FOREST/alpha"* ]] || { echo "FAIL: exec didn't run in alpha"; exit 1; }
[[ "$output" == *"$FOREST/beta"* ]] || { echo "FAIL: exec didn't run in beta"; exit 1; }
echo "  PASS"

echo "Test: wf exec with no command shows usage..."
output=$(_wf_cmd_exec 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"Usage"* ]] || { echo "FAIL: expected usage"; exit 1; }
echo "  PASS"

echo ""
echo "All git operation tests passed!"
