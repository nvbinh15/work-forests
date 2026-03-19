#!/usr/bin/env zsh
# test_core.zsh — Tests for core functions

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../lib/_wf_toml.zsh"
source "$SCRIPT_DIR/../lib/_wf_core.zsh"

# Create temp forest with git repos
TMPDIR_BASE=$(mktemp -d)
trap "rm -rf $TMPDIR_BASE" EXIT

FOREST="$TMPDIR_BASE/test-forest"
mkdir -p "$FOREST"

# Create two fake repos
for name in repo-a repo-b; do
  mkdir -p "$FOREST/$name"
  (cd "$FOREST/$name" && git init -q && git commit --allow-empty -m "init" -q)
done

# Test: resolve forest without manifest (fallback)
echo "Test: _wf_resolve_forest without forest.toml..."
result=$(_wf_resolve_forest "$FOREST")
[[ "$result" = "$FOREST" ]] || { echo "FAIL: got '$result'"; exit 1; }
echo "  PASS"

# Test: _wf_foreach without manifest (scans subdirs)
echo "Test: _wf_foreach scans git subdirs..."
cd "$FOREST"
_test_cb() { echo "visited"; }
output=$(_wf_foreach _test_cb 2>&1) || true
[[ "$output" == *"repo-a"* ]] || { echo "FAIL: missing repo-a in output"; exit 1; }
[[ "$output" == *"repo-b"* ]] || { echo "FAIL: missing repo-b in output"; exit 1; }
echo "  PASS"

# Test: with forest.toml
echo "Test: _wf_resolve_forest with forest.toml..."
cat > "$FOREST/forest.toml" <<'EOF'
[forest]
name = "test"

[repos.repo-a]
path = "repo-a"

[repos.repo-b]
path = "repo-b"
EOF

result=$(_wf_resolve_forest "$FOREST")
[[ "$result" = "$FOREST" ]] || { echo "FAIL: got '$result'"; exit 1; }
echo "  PASS"

# Test: _wf_repo_names with manifest
echo "Test: _wf_repo_names reads from manifest..."
cd "$FOREST"
names=$(_wf_repo_names)
[[ "$names" == *"repo-a"* ]] || { echo "FAIL: missing repo-a"; exit 1; }
[[ "$names" == *"repo-b"* ]] || { echo "FAIL: missing repo-b"; exit 1; }
echo "  PASS"

# Test: version
echo "Test: WF_VERSION is set..."
[[ -n "$WF_VERSION" ]] || { echo "FAIL: WF_VERSION not set"; exit 1; }
echo "  PASS (v$WF_VERSION)"

echo ""
echo "All core tests passed!"
