#!/usr/bin/env zsh
# _wf_core.zsh — Core helpers: foreach, default branch, forest resolution

WF_VERSION="0.1.0"

# Resolve forest root by walking up to find forest.toml
# Falls back to current directory if none found
# Usage: _wf_resolve_forest
_wf_resolve_forest() {
  local dir="${1:-$PWD}"
  dir=$(cd "$dir" 2>/dev/null && pwd)

  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/forest.toml" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  # Fallback: current directory (scan for .git subdirs)
  echo "${1:-$PWD}"
  return 0
}

# Get default branch for current repo (master or main)
_wf_default_branch() {
  local branch
  branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  if [[ -z "$branch" ]]; then
    branch="master"
  fi
  echo "$branch"
}

# Internal helper: iterate repos and run a callback
# If forest.toml exists, uses manifest; otherwise scans for .git subdirs
# Usage: _wf_foreach <callback> [args...]
# Options: --repo NAME to filter to a single repo
_wf_foreach() {
  local filter_repo=""
  local callback=""
  local -a cb_args=()

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo)
        filter_repo="$2"
        shift 2
        ;;
      *)
        if [[ -z "$callback" ]]; then
          callback="$1"
        else
          cb_args+=("$1")
        fi
        shift
        ;;
    esac
  done

  local forest_root
  forest_root=$(_wf_resolve_forest)
  local found=0

  if [[ -f "$forest_root/forest.toml" ]]; then
    # Use manifest
    local repos
    repos=("${(@f)$(_wf_toml_repos "$forest_root/forest.toml")}")

    local repo_path full_path
    for repo_name in "${repos[@]}"; do
      [[ -z "$repo_name" ]] && continue
      [[ -n "$filter_repo" && "$filter_repo" != "$repo_name" ]] && continue

      repo_path=$(_wf_toml_repo_field "$forest_root/forest.toml" "$repo_name" "path")
      [[ -z "$repo_path" ]] && repo_path="$repo_name"

      full_path="$forest_root/$repo_path"
      [[ -d "$full_path/.git" ]] || { print -P "%F{yellow}⚠ $repo_name: not a git repo ($repo_path)%f"; continue; }

      found=1
      print -P "%F{cyan}── $repo_name ──%f"
      (cd "$full_path" && "$callback" "${cb_args[@]}")
      echo
    done
  else
    # Fallback: scan subdirs
    for repo in "$forest_root"/*(N/); do
      [[ -d "$repo/.git" ]] || continue
      local name=$(basename "$repo")
      [[ -n "$filter_repo" && "$filter_repo" != "$name" ]] && continue

      found=1
      print -P "%F{cyan}── $name ──%f"
      (cd "$repo" && "$callback" "${cb_args[@]}")
      echo
    done
  fi

  if [[ $found -eq 0 ]]; then
    if [[ -n "$filter_repo" ]]; then
      echo "error: repo '$filter_repo' not found" >&2
    else
      echo "No git repos found in $forest_root" >&2
    fi
    return 1
  fi
}

# Get repo paths as an array
# Usage: _wf_repo_paths
_wf_repo_paths() {
  local forest_root
  forest_root=$(_wf_resolve_forest)

  if [[ -f "$forest_root/forest.toml" ]]; then
    local repos
    repos=("${(@f)$(_wf_toml_repos "$forest_root/forest.toml")}")
    for repo_name in "${repos[@]}"; do
      [[ -z "$repo_name" ]] && continue
      local repo_path
      repo_path=$(_wf_toml_repo_field "$forest_root/forest.toml" "$repo_name" "path")
      [[ -z "$repo_path" ]] && repo_path="$repo_name"
      echo "$forest_root/$repo_path"
    done
  else
    for repo in "$forest_root"/*(N/); do
      [[ -d "$repo/.git" ]] || continue
      echo "${repo%/}"
    done
  fi
}

# Get repo names as an array
_wf_repo_names() {
  local forest_root
  forest_root=$(_wf_resolve_forest)

  if [[ -f "$forest_root/forest.toml" ]]; then
    _wf_toml_repos "$forest_root/forest.toml"
  else
    for repo in "$forest_root"/*(N/); do
      [[ -d "$repo/.git" ]] || continue
      basename "${repo%/}"
    done
  fi
}
