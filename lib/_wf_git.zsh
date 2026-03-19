#!/usr/bin/env zsh
# _wf_git.zsh — Git operations across forest repos

_wf_cmd_status() {
  local repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_status_cb() {
    local branch=$(git branch --show-current 2>/dev/null || echo "detached")
    local state=""
    if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
      state="%F{green}clean%f"
    else
      state="%F{yellow}dirty%f"
    fi
    local upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
    local ahead_behind=""
    if [[ -n "$upstream" ]]; then
      local ahead=$(git rev-list --count "$upstream"..HEAD 2>/dev/null)
      local behind=$(git rev-list --count HEAD.."$upstream" 2>/dev/null)
      [[ "$ahead" -gt 0 ]] 2>/dev/null && ahead_behind+=" ↑$ahead"
      [[ "$behind" -gt 0 ]] 2>/dev/null && ahead_behind+=" ↓$behind"
    fi
    print -P "  %F{magenta}$branch%f  $state$ahead_behind"
  }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_status_cb
  else
    _wf_foreach _wf_status_cb
  fi
}

_wf_cmd_pull() {
  local rebase_flag="" repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rebase) rebase_flag="--rebase"; shift ;;
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_pull_cb() { git pull $rebase_flag; }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_pull_cb
  else
    _wf_foreach _wf_pull_cb
  fi
}

_wf_cmd_checkout() {
  local create_flag="" branch="" repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -b) create_flag="-b"; shift ;;
      --repo) repo_filter="$2"; shift 2 ;;
      *) [[ -z "$branch" ]] && branch="$1"; shift ;;
    esac
  done

  if [[ -z "$branch" ]]; then
    echo "Usage: wf checkout [-b] <branch> [--repo NAME]"
    return 1
  fi

  _wf_checkout_cb() {
    if [[ -n "$create_flag" ]]; then
      git checkout -b "$branch" 2>&1
    else
      git checkout "$branch" 2>&1 || print -P "  %F{yellow}branch '$branch' not found, staying on $(git branch --show-current)%f"
    fi
  }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_checkout_cb
  else
    _wf_foreach _wf_checkout_cb
  fi
}

_wf_cmd_diff() {
  local repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_diff_cb() { git diff --stat HEAD 2>/dev/null; git diff --cached --stat 2>/dev/null; }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_diff_cb
  else
    _wf_foreach _wf_diff_cb
  fi
}

_wf_cmd_rebase() {
  local repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_rebase_cb() {
    local default_branch=$(_wf_default_branch)
    local current=$(git branch --show-current)
    if [[ "$current" = "$default_branch" ]]; then
      print -P "  %F{yellow}already on $default_branch, pulling instead%f"
      git pull
    else
      git fetch origin "$default_branch" && git rebase "origin/$default_branch"
    fi
  }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_rebase_cb
  else
    _wf_foreach _wf_rebase_cb
  fi
}

_wf_cmd_stash() {
  local action="push" repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      push|pop) action="$1"; shift ;;
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_stash_cb() {
    if [[ "$action" = "pop" ]]; then
      git stash pop
    else
      git stash
    fi
  }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_stash_cb
  else
    _wf_foreach _wf_stash_cb
  fi
}

_wf_cmd_log() {
  local count=3 repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_filter="$2"; shift 2 ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          count="$1"
        fi
        shift ;;
    esac
  done

  _wf_log_cb() { git log --oneline -n "$count"; }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_log_cb
  else
    _wf_foreach _wf_log_cb
  fi
}

_wf_cmd_fetch() {
  local repo_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo_filter="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _wf_fetch_cb() { git fetch --all --prune; }

  if [[ -n "$repo_filter" ]]; then
    _wf_foreach --repo "$repo_filter" _wf_fetch_cb
  else
    _wf_foreach _wf_fetch_cb
  fi
}

_wf_cmd_exec() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: wf exec <command...>"
    return 1
  fi
  _wf_exec_cb() { eval "$@"; }
  _wf_foreach _wf_exec_cb "$@"
}
