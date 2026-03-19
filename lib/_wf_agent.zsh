#!/usr/bin/env zsh
# _wf_agent.zsh — AI agent integration: context, claude-md, agent launchers

_wf_cmd_context() {
  local forest_root
  forest_root=$(_wf_resolve_forest)
  mkdir -p "$forest_root/.wf"

  local outfile="$forest_root/.wf/context.md"
  local forest_name=""
  if [[ -f "$forest_root/forest.toml" ]]; then
    forest_name=$(_wf_toml_get "$forest_root/forest.toml" "forest.name")
  fi
  [[ -z "$forest_name" ]] && forest_name=$(basename "$forest_root")

  {
    echo "# Forest Context: $forest_name"
    echo ""
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Branch alignment check
    echo "## Branch Alignment"
    echo ""
    local branches=()
    local all_aligned=1

    for repo_path in $(_wf_repo_paths); do
      [[ -d "$repo_path/.git" ]] || continue
      local name=$(basename "$repo_path")
      local branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null || echo "detached")
      branches+=("$name:$branch")
    done

    local first_branch=""
    for entry in "${branches[@]}"; do
      local name="${entry%%:*}"
      local branch="${entry#*:}"
      [[ -z "$first_branch" ]] && first_branch="$branch"
      if [[ "$branch" != "$first_branch" ]]; then
        all_aligned=0
      fi
    done

    if [[ $all_aligned -eq 1 && -n "$first_branch" ]]; then
      echo "All repos on: \`$first_branch\`"
    else
      echo "**WARNING: Repos are on different branches!**"
      echo ""
      for entry in "${branches[@]}"; do
        echo "- ${entry%%:*}: \`${entry#*:}\`"
      done
    fi
    echo ""

    # Per-repo status
    echo "## Repository Status"
    echo ""

    for repo_path in $(_wf_repo_paths); do
      [[ -d "$repo_path/.git" ]] || continue
      local name=$(basename "$repo_path")
      local branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null || echo "detached")
      local repo_status="clean"
      if ! (cd "$repo_path" && git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null); then
        repo_status="dirty"
      fi

      echo "### $name"
      echo ""
      echo "- **Branch:** \`$branch\`"
      echo "- **Status:** $repo_status"

      # Uncommitted changes summary
      if [[ "$repo_status" = "dirty" ]]; then
        echo "- **Changes:**"
        echo '```'
        (cd "$repo_path" && git diff --stat HEAD 2>/dev/null)
        (cd "$repo_path" && git diff --cached --stat 2>/dev/null)
        echo '```'
      fi

      # Last 3 commits
      echo "- **Recent commits:**"
      echo '```'
      (cd "$repo_path" && git log --oneline -n 3 2>/dev/null)
      echo '```'
      echo ""
    done

  } > "$outfile"

  print -P "%F{green}✓%f Generated $outfile"
}

_wf_cmd_claude_md() {
  local forest_root
  forest_root=$(_wf_resolve_forest)

  local forest_name="" description=""
  if [[ -f "$forest_root/forest.toml" ]]; then
    forest_name=$(_wf_toml_get "$forest_root/forest.toml" "forest.name")
    description=$(_wf_toml_get "$forest_root/forest.toml" "forest.description")
  fi
  [[ -z "$forest_name" ]] && forest_name=$(basename "$forest_root")

  local outfile="$forest_root/CLAUDE.md"

  {
    echo "# CLAUDE.md — Forest: $forest_name"
    echo ""
    if [[ -n "$description" ]]; then
      echo "$description"
      echo ""
    fi
    echo "This is a multi-repo workspace managed by work-forest."
    echo "Each subdirectory is an independent git repository."
    echo ""

    # Repo overview
    echo "## Repositories"
    echo ""
    for repo_path in $(_wf_repo_paths); do
      [[ -d "$repo_path/.git" ]] || continue
      local name=$(basename "$repo_path")
      local role=""
      if [[ -f "$forest_root/forest.toml" ]]; then
        # Find repo key for this path
        local repos
        repos=("${(@f)$(_wf_toml_repos "$forest_root/forest.toml")}")
        for rkey in "${repos[@]}"; do
          local rpath=$(_wf_toml_repo_field "$forest_root/forest.toml" "$rkey" "path")
          [[ -z "$rpath" ]] && rpath="$rkey"
          if [[ "$rpath" = "$name" || "$rkey" = "$name" ]]; then
            role=$(_wf_toml_repo_field "$forest_root/forest.toml" "$rkey" "role")
            break
          fi
        done
      fi

      local branch=$(cd "$repo_path" && git branch --show-current 2>/dev/null || echo "?")
      echo "### $name"
      [[ -n "$role" ]] && echo "**Role:** $role"
      echo "**Branch:** \`$branch\`"
      echo "**Path:** \`$name/\`"
      echo ""

      # Include first ~50 lines of repo's CLAUDE.md if it exists
      if [[ -f "$repo_path/CLAUDE.md" ]]; then
        echo "<details>"
        echo "<summary>$name/CLAUDE.md (excerpt)</summary>"
        echo ""
        head -50 "$repo_path/CLAUDE.md"
        echo ""
        echo "</details>"
        echo ""
      fi
    done

    # Cross-repo relationships
    if [[ -f "$forest_root/forest.toml" ]]; then
      local rels
      rels=$(_wf_toml_relationships "$forest_root/forest.toml")
      if [[ -n "$rels" ]]; then
        echo "## Cross-Repo Relationships"
        echo ""
        echo "$rels" | while IFS= read -r line; do
          echo "- $line"
        done
        echo ""
      fi
    fi

    # Cross-repo rules
    echo "## Cross-Repo Rules"
    echo ""
    echo "- When making API changes, check all consumer repos for breaking changes."
    echo "- Run \`wf status\` to verify all repos are on the correct feature branch before committing."
    echo "- Use \`wf context\` to regenerate the state snapshot after significant changes."
    echo ""

    # Current state
    echo "## Current State"
    echo ""
    echo "Run \`wf context\` for a detailed state snapshot, or \`wf status\` for a quick overview."
    echo ""

  } > "$outfile"

  print -P "%F{green}✓%f Generated $outfile"
}

_wf_cmd_agent() {
  local agent_type="${1:-claude}"
  shift 2>/dev/null
  local prompt="" resume=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prompt) prompt="$2"; shift 2 ;;
      --resume) resume=1; shift ;;
      *) shift ;;
    esac
  done

  local forest_root
  forest_root=$(_wf_resolve_forest)

  case "$agent_type" in
    claude)
      # Refresh context
      _wf_cmd_context
      _wf_cmd_claude_md

      # Build --add-dir flags
      local -a dirs=()
      for repo_path in $(_wf_repo_paths); do
        [[ -d "$repo_path/.git" ]] || continue
        dirs+=("--add-dir" "$repo_path")
      done

      local -a cmd=(claude)
      cmd+=("${dirs[@]}")

      if [[ $resume -eq 1 ]]; then
        cmd+=("-c")
      fi

      if [[ -n "$prompt" ]]; then
        cmd+=("-p" "$prompt")
      fi

      print -P "%F{cyan}Launching:  ${cmd[*]}%f"
      (cd "$forest_root" && "${cmd[@]}")
      ;;

    cursor)
      _wf_generate_workspace
      _wf_generate_cursorrules

      local ws_file="$forest_root/.wf/forest.code-workspace"
      if command -v cursor &>/dev/null; then
        print -P "%F{cyan}Opening workspace in Cursor...%f"
        cursor "$ws_file"
      else
        print -P "%F{yellow}Cursor not found in PATH. Open manually: $ws_file%f"
      fi
      ;;

    codex)
      _wf_cmd_context

      if command -v codex &>/dev/null; then
        local -a cmd=(codex)
        [[ -n "$prompt" ]] && cmd+=("$prompt")
        print -P "%F{cyan}Launching Codex from forest root...%f"
        (cd "$forest_root" && "${cmd[@]}")
      else
        print -P "%F{yellow}Codex not found in PATH.%f"
        return 1
      fi
      ;;

    *)
      echo "Unknown agent type: $agent_type"
      echo "Supported: claude, cursor, codex"
      return 1
      ;;
  esac
}

_wf_generate_workspace() {
  local forest_root
  forest_root=$(_wf_resolve_forest)
  mkdir -p "$forest_root/.wf"

  local ws_file="$forest_root/.wf/forest.code-workspace"

  {
    echo "{"
    echo '  "folders": ['

    local first=1
    for repo_path in $(_wf_repo_paths); do
      [[ -d "$repo_path/.git" ]] || continue
      local name=$(basename "$repo_path")
      local rel_path
      rel_path=$(python3 -c "import os.path; print(os.path.relpath('$repo_path', '$forest_root/.wf'))" 2>/dev/null || echo "../$name")

      [[ $first -eq 0 ]] && echo ","
      first=0
      printf '    {"path": "%s", "name": "%s"}' "$rel_path" "$name"
    done

    echo ""
    echo "  ],"
    echo '  "settings": {}'
    echo "}"
  } > "$ws_file"

  print -P "%F{green}✓%f Generated $ws_file"
}

_wf_generate_cursorrules() {
  local forest_root
  forest_root=$(_wf_resolve_forest)

  local forest_name=""
  if [[ -f "$forest_root/forest.toml" ]]; then
    forest_name=$(_wf_toml_get "$forest_root/forest.toml" "forest.name")
  fi
  [[ -z "$forest_name" ]] && forest_name=$(basename "$forest_root")

  local outfile="$forest_root/.cursorrules"

  {
    echo "# Cursor Rules — Forest: $forest_name"
    echo ""
    echo "This is a multi-repo workspace. Each subdirectory is an independent git repository."
    echo ""
    echo "## Repositories"
    echo ""

    for repo_path in $(_wf_repo_paths); do
      [[ -d "$repo_path/.git" ]] || continue
      local name=$(basename "$repo_path")
      local role=""
      if [[ -f "$forest_root/forest.toml" ]]; then
        local repos
        repos=("${(@f)$(_wf_toml_repos "$forest_root/forest.toml")}")
        for rkey in "${repos[@]}"; do
          local rpath=$(_wf_toml_repo_field "$forest_root/forest.toml" "$rkey" "path")
          [[ -z "$rpath" ]] && rpath="$rkey"
          if [[ "$rpath" = "$name" || "$rkey" = "$name" ]]; then
            role=$(_wf_toml_repo_field "$forest_root/forest.toml" "$rkey" "role")
            break
          fi
        done
      fi

      echo "- **$name/** ($role): $(cd "$repo_path" && git branch --show-current 2>/dev/null)"

      # Include cursor rules from repo if they exist
      local repo_rules=""
      for rfile in "$repo_path/.cursorrules" "$repo_path/.cursor/rules/"*.mdc(N); do
        if [[ -f "$rfile" ]]; then
          repo_rules="$rfile"
          break
        fi
      done

      if [[ -n "$repo_rules" ]]; then
        echo "  - See: $repo_rules"
      fi
    done

    echo ""
    echo "## Rules"
    echo ""
    echo "- When making changes across repos, ensure API contracts remain consistent."
    echo "- Each repo has its own git history — commit in the correct repo."
    echo "- Check forest.toml for repo relationships and roles."
    echo ""

  } > "$outfile"

  print -P "%F{green}✓%f Generated $outfile"
}

_wf_cmd_open() {
  local editor="${1:-cursor}"
  local forest_root
  forest_root=$(_wf_resolve_forest)

  case "$editor" in
    cursor)
      _wf_generate_workspace
      _wf_generate_cursorrules
      local ws_file="$forest_root/.wf/forest.code-workspace"
      if command -v cursor &>/dev/null; then
        cursor "$ws_file"
      else
        print -P "%F{yellow}Cursor not found. Open: $ws_file%f"
      fi
      ;;
    code)
      _wf_generate_workspace
      local ws_file="$forest_root/.wf/forest.code-workspace"
      if command -v code &>/dev/null; then
        code "$ws_file"
      else
        print -P "%F{yellow}VS Code not found. Open: $ws_file%f"
      fi
      ;;
    idea)
      if command -v idea &>/dev/null; then
        idea "$forest_root"
      else
        print -P "%F{yellow}IntelliJ IDEA not found.%f"
      fi
      ;;
    *)
      echo "Unknown editor: $editor"
      echo "Supported: cursor, code, idea"
      return 1
      ;;
  esac
}
