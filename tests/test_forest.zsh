#!/usr/bin/env zsh
# test_forest.zsh — Tests for forest management: init, add, remove, list

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../lib/_wf_toml.zsh"
source "$SCRIPT_DIR/../lib/_wf_core.zsh"
source "$SCRIPT_DIR/../lib/_wf_git.zsh"
source "$SCRIPT_DIR/../lib/_wf_forest.zsh"

# ── Setup: temp directory with git repos ──

TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

FOREST="$TMPDIR_BASE/my-feature"
mkdir -p "$FOREST"

# Create three repos simulating a real forest
for name in backend frontend-app e2e-tests; do
  mkdir -p "$FOREST/$name"
  (
    cd "$FOREST/$name"
    git init -q
    git commit --allow-empty -m "init $name" -q
  )
done

cd "$FOREST"

# ── Tests: wf init ──

echo "Test: wf init auto-detects repos..."
output=$(_wf_cmd_init 2>&1)
[[ -f "$FOREST/forest.toml" ]] || { echo "FAIL: forest.toml not created"; exit 1; }
[[ "$output" == *"3 repo(s)"* ]] || { echo "FAIL: should detect 3 repos, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf init creates .wf directory..."
[[ -d "$FOREST/.wf" ]] || { echo "FAIL: .wf/ not created"; exit 1; }
echo "  PASS"

echo "Test: wf init creates .gitignore..."
[[ -f "$FOREST/.gitignore" ]] || { echo "FAIL: .gitignore not created"; exit 1; }
content=$(cat "$FOREST/.gitignore")
[[ "$content" == *".wf/"* ]] || { echo "FAIL: .gitignore missing .wf/"; exit 1; }
[[ "$content" == *"CLAUDE.md"* ]] || { echo "FAIL: .gitignore missing CLAUDE.md"; exit 1; }
[[ "$content" == *".cursorrules"* ]] || { echo "FAIL: .gitignore missing .cursorrules"; exit 1; }
echo "  PASS"

echo "Test: wf init uses --name flag..."
toml_name=$(_wf_toml_get "$FOREST/forest.toml" "forest.name")
[[ "$toml_name" = "my-feature" ]] || { echo "FAIL: name should be 'my-feature', got '$toml_name'"; exit 1; }
echo "  PASS"

echo "Test: wf init guesses roles from repo names..."
be_role=$(_wf_toml_repo_field "$FOREST/forest.toml" "backend" "role")
fe_role=$(_wf_toml_repo_field "$FOREST/forest.toml" "frontend-app" "role")
e2e_role=$(_wf_toml_repo_field "$FOREST/forest.toml" "e2e-tests" "role")
[[ "$be_role" = "backend" ]] || { echo "FAIL: backend role='$be_role'"; exit 1; }
[[ "$fe_role" = "frontend" ]] || { echo "FAIL: frontend-app role='$fe_role'"; exit 1; }
[[ "$e2e_role" = "e2e" ]] || { echo "FAIL: e2e-tests role='$e2e_role'"; exit 1; }
echo "  PASS"

echo "Test: wf init refuses to overwrite existing forest.toml..."
output=$(_wf_cmd_init 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"already exists"* ]] || { echo "FAIL: expected 'already exists', got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf init with --name flag..."
rm "$FOREST/forest.toml"
output=$(_wf_cmd_init --name custom-name 2>&1)
toml_name=$(_wf_toml_get "$FOREST/forest.toml" "forest.name")
[[ "$toml_name" = "custom-name" ]] || { echo "FAIL: name should be 'custom-name', got '$toml_name'"; exit 1; }
echo "  PASS"

echo "Test: wf init with explicit directory..."
rm "$FOREST/forest.toml"
FOREST2="$TMPDIR_BASE/other"
mkdir -p "$FOREST2/svc"
(cd "$FOREST2/svc" && git init -q && git commit --allow-empty -m "init" -q)
output=$(_wf_cmd_init "$FOREST2" 2>&1)
[[ -f "$FOREST2/forest.toml" ]] || { echo "FAIL: forest.toml not created in other dir"; exit 1; }
rm -rf "$FOREST2"
echo "  PASS"

# Re-init for remaining tests
cd "$FOREST"
_wf_cmd_init --name my-feature >/dev/null 2>&1

# ── Tests: wf list ──

echo "Test: wf list shows all repos..."
output=$(_wf_cmd_list 2>&1)
[[ "$output" == *"backend"* ]] || { echo "FAIL: missing backend"; exit 1; }
[[ "$output" == *"frontend-app"* ]] || { echo "FAIL: missing frontend-app"; exit 1; }
[[ "$output" == *"e2e-tests"* ]] || { echo "FAIL: missing e2e-tests"; exit 1; }
echo "  PASS"

echo "Test: wf list shows forest name..."
output=$(_wf_cmd_list 2>&1)
[[ "$output" == *"my-feature"* ]] || { echo "FAIL: missing forest name"; exit 1; }
echo "  PASS"

echo "Test: wf list --json produces valid structure..."
output=$(_wf_cmd_list --json 2>&1)
[[ "$output" == "["* ]] || { echo "FAIL: should start with ["; exit 1; }
[[ "$output" == *"]" ]] || { echo "FAIL: should end with ]"; exit 1; }
[[ "$output" == *'"name": "backend"'* ]] || { echo "FAIL: missing backend in JSON"; exit 1; }
[[ "$output" == *'"role": "backend"'* ]] || { echo "FAIL: missing role in JSON"; exit 1; }
[[ "$output" == *'"status": "clean"'* ]] || { echo "FAIL: missing status in JSON"; exit 1; }
echo "  PASS"

echo "Test: wf list shows correct branch..."
DEFAULT_BRANCH=$(cd "$FOREST/backend" && git branch --show-current)
(cd "$FOREST/backend" && git checkout -b feat/test -q 2>/dev/null)
output=$(_wf_cmd_list --json 2>&1)
[[ "$output" == *'"branch": "feat/test"'* ]] || { echo "FAIL: branch not shown, got: $output"; exit 1; }
(cd "$FOREST/backend" && git checkout "$DEFAULT_BRANCH" -q 2>/dev/null)
echo "  PASS"

echo "Test: wf list detects dirty repos..."
echo "change" >> "$FOREST/backend/dirty.txt"
(cd "$FOREST/backend" && git add dirty.txt)
output=$(_wf_cmd_list --json 2>&1)
[[ "$output" == *'"status": "dirty"'* ]] || { echo "FAIL: should detect dirty status"; exit 1; }
(cd "$FOREST/backend" && git reset HEAD -- dirty.txt -q && rm -f dirty.txt)
echo "  PASS"

# ── Tests: wf add ──

echo "Test: wf add registers a new repo..."
# Create a new repo not yet in manifest
mkdir -p "$FOREST/infra"
(cd "$FOREST/infra" && git init -q && git commit --allow-empty -m "init infra" -q)
output=$(_wf_cmd_add infra --role infra 2>&1)
[[ "$output" == *"Added infra"* ]] || { echo "FAIL: expected confirmation, got: $output"; exit 1; }
# Verify in TOML
repos=$(_wf_toml_repos "$FOREST/forest.toml")
[[ "$repos" == *"infra"* ]] || { echo "FAIL: infra not in forest.toml"; exit 1; }
role=$(_wf_toml_repo_field "$FOREST/forest.toml" "infra" "role")
[[ "$role" = "infra" ]] || { echo "FAIL: infra role='$role'"; exit 1; }
echo "  PASS"

echo "Test: wf add rejects duplicate..."
output=$(_wf_cmd_add infra 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"already registered"* ]] || { echo "FAIL: expected duplicate error, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf add rejects non-git directory..."
mkdir -p "$FOREST/not-a-repo"
output=$(_wf_cmd_add not-a-repo 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"not a git repository"* ]] || { echo "FAIL: expected error, got: $output"; exit 1; }
rmdir "$FOREST/not-a-repo"
echo "  PASS"

# ── Tests: wf remove ──

echo "Test: wf remove unregisters a repo..."
output=$(_wf_cmd_remove infra 2>&1)
[[ "$output" == *"Removed infra"* ]] || { echo "FAIL: expected confirmation, got: $output"; exit 1; }
repos=$(_wf_toml_repos "$FOREST/forest.toml")
[[ "$repos" != *"infra"* ]] || { echo "FAIL: infra still in forest.toml"; exit 1; }
echo "  PASS"

echo "Test: wf remove keeps other repos intact..."
repos=$(_wf_toml_repos "$FOREST/forest.toml")
[[ "$repos" == *"backend"* ]] || { echo "FAIL: backend lost after remove"; exit 1; }
[[ "$repos" == *"frontend-app"* ]] || { echo "FAIL: frontend-app lost after remove"; exit 1; }
echo "  PASS"

echo "Test: wf remove keeps files on disk..."
[[ -d "$FOREST/infra/.git" ]] || { echo "FAIL: infra directory should still exist"; exit 1; }
echo "  PASS"

echo "Test: wf remove rejects unknown repo..."
output=$(_wf_cmd_remove nonexistent 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"not in forest.toml"* ]] || { echo "FAIL: expected error, got: $output"; exit 1; }
echo "  PASS"

echo "Test: wf remove with no args shows usage..."
output=$(_wf_cmd_remove 2>&1) && { echo "FAIL: should have failed"; exit 1; } || true
[[ "$output" == *"Usage"* ]] || { echo "FAIL: expected usage, got: $output"; exit 1; }
echo "  PASS"

# ── Tests: wf init with empty directory ──

echo "Test: wf init in empty directory creates minimal forest.toml..."
EMPTY="$TMPDIR_BASE/empty-forest"
mkdir -p "$EMPTY"
cd "$EMPTY"
output=$(_wf_cmd_init 2>&1)
[[ -f "$EMPTY/forest.toml" ]] || { echo "FAIL: forest.toml not created"; exit 1; }
[[ "$output" == *"No git repos"* ]] || { echo "FAIL: should warn about no repos"; exit 1; }
# Verify the TOML is valid
toml_name=$(_wf_toml_get "$EMPTY/forest.toml" "forest.name")
[[ "$toml_name" = "empty-forest" ]] || { echo "FAIL: name='$toml_name'"; exit 1; }
cd "$FOREST"
echo "  PASS"

# ── Tests: wf list without manifest (fallback) ──

echo "Test: wf list without forest.toml scans subdirs..."
NOTOML="$TMPDIR_BASE/no-toml"
mkdir -p "$NOTOML/svc-a" "$NOTOML/svc-b"
(cd "$NOTOML/svc-a" && git init -q && git commit --allow-empty -m "init" -q)
(cd "$NOTOML/svc-b" && git init -q && git commit --allow-empty -m "init" -q)
cd "$NOTOML"
output=$(_wf_cmd_list 2>&1) || true
[[ "$output" == *"svc-a"* ]] || { echo "FAIL: missing svc-a"; exit 1; }
[[ "$output" == *"svc-b"* ]] || { echo "FAIL: missing svc-b"; exit 1; }
cd "$FOREST"
echo "  PASS"

echo ""
echo "All forest management tests passed!"
