#!/usr/bin/env zsh
# _wf_toml.zsh — Minimal TOML parser (awk-based, zero deps)
# Handles [table], [table.subtable], key = "value", arrays, and inline tables

# Parse a TOML file and output key=value pairs in flat dotted notation
# Usage: _wf_toml_parse <file>
# Output: table.key=value (one per line)
_wf_toml_parse() {
  local file="$1"
  [[ -f "$file" ]] || { echo "error: file not found: $file" >&2; return 1; }

  awk '
    BEGIN { section = "" }

    # Skip comments and blank lines
    /^[[:space:]]*(#|$)/ { next }

    # Section header: [foo] or [foo.bar]
    /^[[:space:]]*\[/ {
      gsub(/^[[:space:]]*\[/, "")
      gsub(/\][[:space:]]*$/, "")
      gsub(/[[:space:]]/, "")
      section = $0
      next
    }

    # Key = value
    /=/ {
      # Split on first =
      idx = index($0, "=")
      key = substr($0, 1, idx - 1)
      val = substr($0, idx + 1)

      # Trim whitespace
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)

      # Remove surrounding quotes from string values
      if (val ~ /^".*"$/) {
        val = substr(val, 2, length(val) - 2)
      }

      # Build full key
      if (section != "") {
        fullkey = section "." key
      } else {
        fullkey = key
      }

      print fullkey "=" val
    }
  ' "$file"
}

# Get a specific value from a TOML file
# Usage: _wf_toml_get <file> <dotted.key>
_wf_toml_get() {
  local file="$1" key="$2"
  _wf_toml_parse "$file" | awk -F= -v k="$key" '$1 == k { print substr($0, length(k)+2); exit }'
}

# List all repo names from forest.toml [repos.*] sections
# Usage: _wf_toml_repos <file>
_wf_toml_repos() {
  local file="$1"
  _wf_toml_parse "$file" | awk -F= '
    /^repos\./ {
      split($1, parts, ".")
      if (parts[2] != "" && !seen[parts[2]]++) {
        print parts[2]
      }
    }
  '
}

# Get a repo field: _wf_toml_repo_field <file> <repo_name> <field>
_wf_toml_repo_field() {
  local file="$1" repo="$2" field="$3"
  _wf_toml_get "$file" "repos.${repo}.${field}"
}

# List all relationship entries
# Usage: _wf_toml_relationships <file>
_wf_toml_relationships() {
  local file="$1"
  _wf_toml_parse "$file" | grep '^relationships\.' || true
}
