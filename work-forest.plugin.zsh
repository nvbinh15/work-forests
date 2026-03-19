#!/usr/bin/env zsh
# work-forest.plugin.zsh — Oh-my-zsh / manual source entry point

WF_PLUGIN_DIR="${0:A:h}"

# Source libraries
source "$WF_PLUGIN_DIR/lib/_wf_toml.zsh"
source "$WF_PLUGIN_DIR/lib/_wf_core.zsh"
source "$WF_PLUGIN_DIR/lib/_wf_git.zsh"
source "$WF_PLUGIN_DIR/lib/_wf_forest.zsh"
source "$WF_PLUGIN_DIR/lib/_wf_agent.zsh"

# Main wf function (dispatches subcommands)
wf() {
  local cmd="${1:-help}"
  shift 2>/dev/null

  case "$cmd" in
    init)       _wf_cmd_init "$@" ;;
    clone)      _wf_cmd_clone "$@" ;;
    add)        _wf_cmd_add "$@" ;;
    remove)     _wf_cmd_remove "$@" ;;
    list|ls)    _wf_cmd_list "$@" ;;
    status|st)  _wf_cmd_status "$@" ;;
    pull)       _wf_cmd_pull "$@" ;;
    checkout|co) _wf_cmd_checkout "$@" ;;
    diff)       _wf_cmd_diff "$@" ;;
    rebase)     _wf_cmd_rebase "$@" ;;
    stash)      _wf_cmd_stash "$@" ;;
    log)        _wf_cmd_log "$@" ;;
    fetch)      _wf_cmd_fetch "$@" ;;
    exec)       _wf_cmd_exec "$@" ;;
    context)    _wf_cmd_context ;;
    claude-md)  _wf_cmd_claude_md ;;
    agent)      _wf_cmd_agent "$@" ;;
    open)       _wf_cmd_open "$@" ;;
    help|--help|-h)
      # Inline help for shell function
      source "$WF_PLUGIN_DIR/bin/wf" help 2>/dev/null || {
        print -P "%F{cyan}work-forest%f v$WF_VERSION"
        echo "Run 'wf help' for usage."
      }
      ;;
    version|--version|-v) echo "work-forest v$WF_VERSION" ;;
    *)
      echo "Unknown command: $cmd"
      echo "Run 'wf help' for usage."
      return 1
      ;;
  esac
}

# Backward-compat aliases (matches existing wf* functions from .zshrc)
alias wfpull='wf pull'
alias wfstatus='wf status'
alias wfcheckout='wf checkout'
alias wfdiff='wf diff'
alias wfrebase='wf rebase'
alias wfstash='wf stash'
alias wfstashpop='wf stash pop'
alias wflog='wf log'
alias wfexec='wf exec'
alias wfhelp='wf help'

# Source completions if available
if [[ -f "$WF_PLUGIN_DIR/completions/_wf" ]]; then
  fpath=("$WF_PLUGIN_DIR/completions" $fpath)
fi
