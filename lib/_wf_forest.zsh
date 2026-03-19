#!/usr/bin/env zsh
# _wf_forest.zsh — Forest management: init, clone, add, remove, list

_wf_cmd_init() {
  local name="" dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) dir="$1"; shift ;;
    esac
  done

  dir="${dir:-.}"
  dir=$(cd "$dir" 2>/dev/null && pwd)

  if [[ -f "$dir/forest.toml" ]]; then
    echo "forest.toml already exists in $dir"
    return 1
  fi

  [[ -z "$name" ]] && name=$(basename "$dir")

  # Auto-detect git repos
  local repos=()
  local sub
  for sub in "$dir"/*(N/); do
    [[ -d "$sub/.git" ]] || continue
    repos+=($(basename "$sub"))
  done

  if [[ ${#repos[@]} -eq 0 ]]; then
    echo "No git repos found in $dir"
    echo "Creating empty forest.toml — use 'wf clone' or 'wf add' to add repos."
  fi

  # Generate forest.toml
  {
    echo "[forest]"
    echo "name = \"$name\""
    echo "description = \"\""
    echo "branch_pattern = \"feat/{name}\""
    echo ""

    for repo in "${repos[@]}"; do
      local url="" default_branch="main" role=""

      # Try to detect remote URL and default branch
      if [[ -d "$dir/$repo/.git" ]]; then
        url=$(cd "$dir/$repo" && git remote get-url origin 2>/dev/null) || url=""
        default_branch=$(cd "$dir/$repo" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || default_branch="main"
        [[ -z "$default_branch" ]] && default_branch="main"
      fi

      # Guess role from repo name
      case "$repo" in
        *backend*|*be*|*api*|*server*) role="backend" ;;
        *frontend*|*fe*|*web*|*ui*|*app*) role="frontend" ;;
        *e2e*|*test*|*qa*) role="e2e" ;;
        *infra*|*deploy*|*ops*) role="infra" ;;
        *) role="" ;;
      esac

      echo "[repos.$repo]"
      [[ -n "$url" ]] && echo "url = \"$url\""
      echo "path = \"$repo\""
      [[ -n "$role" ]] && echo "role = \"$role\""
      echo "default_branch = \"$default_branch\""
      echo ""
    done
  } > "$dir/forest.toml"

  # Create .wf directory
  mkdir -p "$dir/.wf"

  # Create .gitignore if it doesn't exist
  if [[ ! -f "$dir/.gitignore" ]]; then
    {
      echo ".wf/"
      echo "CLAUDE.md"
      echo ".cursorrules"
    } > "$dir/.gitignore"
  fi

  print -P "%F{green}✓%f Initialized forest %F{cyan}$name%f with ${#repos[@]} repo(s)"
  for repo in "${repos[@]}"; do
    print -P "  %F{magenta}$repo%f"
  done
  echo ""
  echo "Edit forest.toml to customize repo roles and relationships."
}

_wf_cmd_clone() {
  local url="" name="" role=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --as) name="$2"; shift 2 ;;
      --role) role="$2"; shift 2 ;;
      *) url="$1"; shift ;;
    esac
  done

  if [[ -z "$url" ]]; then
    echo "Usage: wf clone <url> [--as NAME] [--role ROLE]"
    return 1
  fi

  local forest_root
  forest_root=$(_wf_resolve_forest)

  # Derive name from URL if not specified
  if [[ -z "$name" ]]; then
    name=$(basename "$url" .git)
  fi

  # Clone
  print -P "%F{cyan}Cloning $url as $name...%f"
  git clone "$url" "$forest_root/$name" || return 1

  # Add to forest.toml if it exists
  if [[ -f "$forest_root/forest.toml" ]]; then
    local default_branch
    default_branch=$(cd "$forest_root/$name" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    [[ -z "$default_branch" ]] && default_branch="main"

    {
      echo ""
      echo "[repos.$name]"
      echo "url = \"$url\""
      echo "path = \"$name\""
      [[ -n "$role" ]] && echo "role = \"$role\""
      echo "default_branch = \"$default_branch\""
    } >> "$forest_root/forest.toml"

    print -P "%F{green}✓%f Registered $name in forest.toml"
  else
    print -P "%F{yellow}⚠ No forest.toml found. Run 'wf init' first to create one.%f"
  fi
}

_wf_cmd_add() {
  local dir="" role=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) role="$2"; shift 2 ;;
      *) dir="$1"; shift ;;
    esac
  done

  dir="${dir:-.}"

  local forest_root
  forest_root=$(_wf_resolve_forest)

  # Resolve the directory
  local full_path
  if [[ "$dir" = /* ]]; then
    full_path="$dir"
  else
    full_path="$forest_root/$dir"
  fi

  if [[ ! -d "$full_path/.git" ]]; then
    echo "error: $dir is not a git repository"
    return 1
  fi

  local name=$(basename "$full_path")
  local rel_path
  rel_path=$(python3 -c "import os.path; print(os.path.relpath('$full_path', '$forest_root'))" 2>/dev/null || echo "$name")

  if [[ ! -f "$forest_root/forest.toml" ]]; then
    echo "error: no forest.toml found. Run 'wf init' first."
    return 1
  fi

  # Check if already registered
  if _wf_toml_repos "$forest_root/forest.toml" | grep -qx "$name"; then
    echo "error: $name is already registered in forest.toml"
    return 1
  fi

  local url
  url=$(cd "$full_path" && git remote get-url origin 2>/dev/null || echo "")
  local default_branch
  default_branch=$(cd "$full_path" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  [[ -z "$default_branch" ]] && default_branch="main"

  {
    echo ""
    echo "[repos.$name]"
    [[ -n "$url" ]] && echo "url = \"$url\""
    echo "path = \"$rel_path\""
    [[ -n "$role" ]] && echo "role = \"$role\""
    echo "default_branch = \"$default_branch\""
  } >> "$forest_root/forest.toml"

  print -P "%F{green}✓%f Added $name to forest.toml"
}

_wf_cmd_remove() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: wf remove <name>"
    return 1
  fi

  local forest_root
  forest_root=$(_wf_resolve_forest)

  if [[ ! -f "$forest_root/forest.toml" ]]; then
    echo "error: no forest.toml found"
    return 1
  fi

  if ! _wf_toml_repos "$forest_root/forest.toml" | grep -qx "$name"; then
    echo "error: $name is not in forest.toml"
    return 1
  fi

  # Remove the [repos.NAME] section from forest.toml
  local tmpfile=$(mktemp)
  awk -v repo="$name" '
    BEGIN { skip = 0 }
    /^\[repos\./ {
      if (index($0, "[repos." repo "]") > 0) {
        skip = 1
        next
      } else {
        skip = 0
      }
    }
    /^\[/ && !/^\[repos\./ { skip = 0 }
    !skip { print }
  ' "$forest_root/forest.toml" > "$tmpfile"

  mv "$tmpfile" "$forest_root/forest.toml"

  print -P "%F{green}✓%f Removed $name from forest.toml (files kept on disk)"
}

_wf_cmd_list() {
  local json_output=0
  [[ "$1" = "--json" ]] && json_output=1

  local forest_root
  forest_root=$(_wf_resolve_forest)

  if [[ $json_output -eq 1 ]]; then
    echo "["
  else
    local forest_name=""
    if [[ -f "$forest_root/forest.toml" ]]; then
      forest_name=$(_wf_toml_get "$forest_root/forest.toml" "forest.name")
    fi
    [[ -z "$forest_name" ]] && forest_name=$(basename "$forest_root")
    print -P "%F{cyan}Forest: $forest_name%f ($forest_root)\n"
    printf "%-15s %-20s %-10s %-8s %s\n" "NAME" "BRANCH" "ROLE" "STATUS" "PATH"
    printf "%-15s %-20s %-10s %-8s %s\n" "----" "------" "----" "------" "----"
  fi

  local repos_found=0 first=1
  local -a repo_entries=()
  local rp rr n entry r_name rest r_path r_role full_path branch repo_status

  # Collect repo entries as "name|path|role"
  if [[ -f "$forest_root/forest.toml" ]]; then
    local repos
    repos=("${(@f)$(_wf_toml_repos "$forest_root/forest.toml")}")
    for repo_name in "${repos[@]}"; do
      [[ -z "$repo_name" ]] && continue
      rp=$(_wf_toml_repo_field "$forest_root/forest.toml" "$repo_name" "path")
      rr=$(_wf_toml_repo_field "$forest_root/forest.toml" "$repo_name" "role")
      [[ -z "$rp" ]] && rp="$repo_name"
      repo_entries+=("${repo_name}|${rp}|${rr}")
    done
  else
    for repo in "$forest_root"/*(N/); do
      [[ -d "$repo/.git" ]] || continue
      n=$(basename "$repo")
      repo_entries+=("${n}|${n}|")
    done
  fi

  # Process each entry
  for entry in "${repo_entries[@]}"; do
    r_name="${entry%%|*}"
    rest="${entry#*|}"
    r_path="${rest%%|*}"
    r_role="${rest#*|}"
    full_path="$forest_root/$r_path"

    [[ -d "$full_path/.git" ]] || continue
    repos_found=1

    branch=$(cd "$full_path" && git branch --show-current 2>/dev/null) || branch=""
    [[ -z "$branch" ]] && branch="detached"

    repo_status="clean"
    if ! (cd "$full_path" && git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null); then
      repo_status="dirty"
    fi

    if [[ $json_output -eq 1 ]]; then
      [[ $first -eq 0 ]] && echo ","
      first=0
      printf '  {"name": "%s", "path": "%s", "role": "%s", "branch": "%s", "status": "%s"}' \
        "$r_name" "$r_path" "$r_role" "$branch" "$repo_status"
    else
      if [[ "$repo_status" = "clean" ]]; then
        printf "%-15s %-20s %-10s \033[32m%-8s\033[0m %s\n" "$r_name" "$branch" "$r_role" "$repo_status" "$r_path"
      else
        printf "%-15s %-20s %-10s \033[33m%-8s\033[0m %s\n" "$r_name" "$branch" "$r_role" "$repo_status" "$r_path"
      fi
    fi
  done

  if [[ $json_output -eq 1 ]]; then
    echo ""
    echo "]"
  fi

  [[ $repos_found -eq 0 ]] && echo "No repos found." && return 1
  return 0
}
