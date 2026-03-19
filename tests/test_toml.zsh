#!/usr/bin/env zsh
# test_toml.zsh — Tests for TOML parser

set -e

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../lib/_wf_toml.zsh"

# Create temp test file
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

cat > "$TMPFILE" <<'EOF'
[forest]
name = "test-forest"
description = "A test forest"
branch_pattern = "feat/{name}"

[repos.be]
url = "git@github.com:org/backend.git"
path = "be"
role = "backend"
default_branch = "master"

[repos.fe-v2]
url = "git@github.com:org/frontend-v2.git"
path = "fe-v2"
role = "frontend"
default_branch = "main"
EOF

# Test: parse outputs correct keys
echo "Test: _wf_toml_parse produces key=value pairs..."
output=$(_wf_toml_parse "$TMPFILE")
[[ "$output" == *"forest.name=test-forest"* ]] || { echo "FAIL: forest.name"; exit 1; }
[[ "$output" == *"repos.be.path=be"* ]] || { echo "FAIL: repos.be.path"; exit 1; }
[[ "$output" == *"repos.fe-v2.role=frontend"* ]] || { echo "FAIL: repos.fe-v2.role"; exit 1; }
echo "  PASS"

# Test: get specific value
echo "Test: _wf_toml_get retrieves specific keys..."
val=$(_wf_toml_get "$TMPFILE" "forest.name")
[[ "$val" = "test-forest" ]] || { echo "FAIL: got '$val'"; exit 1; }

val=$(_wf_toml_get "$TMPFILE" "repos.be.default_branch")
[[ "$val" = "master" ]] || { echo "FAIL: got '$val'"; exit 1; }
echo "  PASS"

# Test: list repos
echo "Test: _wf_toml_repos lists repo names..."
repos=$(_wf_toml_repos "$TMPFILE")
[[ "$repos" == *"be"* ]] || { echo "FAIL: missing be"; exit 1; }
[[ "$repos" == *"fe-v2"* ]] || { echo "FAIL: missing fe-v2"; exit 1; }
echo "  PASS"

# Test: repo field
echo "Test: _wf_toml_repo_field gets repo fields..."
val=$(_wf_toml_repo_field "$TMPFILE" "be" "role")
[[ "$val" = "backend" ]] || { echo "FAIL: got '$val'"; exit 1; }
val=$(_wf_toml_repo_field "$TMPFILE" "fe-v2" "url")
[[ "$val" = "git@github.com:org/frontend-v2.git" ]] || { echo "FAIL: got '$val'"; exit 1; }
echo "  PASS"

# Test: missing file
echo "Test: _wf_toml_parse handles missing file..."
_wf_toml_parse "/nonexistent/file.toml" 2>/dev/null && { echo "FAIL: should error"; exit 1; }
echo "  PASS"

echo ""
echo "All TOML parser tests passed!"
