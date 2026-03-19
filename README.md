# work-forest

Multi-repo feature workspace tool. When a feature spans multiple repos (backend + frontend + e2e), clone them into a single "forest" directory and operate on them together.

**Key features:**
- Single `wf` command for git operations across all repos
- `forest.toml` manifest to declare repo relationships
- AI agent integration (Claude Code, Cursor, Codex) with cross-repo context

## Quick Start

```bash
# Install
git clone https://github.com/user/work-forest.git ~/.oh-my-zsh/custom/plugins/work-forest
# Add to .zshrc: plugins=(... work-forest)

# Or manual install
source /path/to/work-forest/work-forest.plugin.zsh

# Initialize a forest
mkdir my-feature && cd my-feature
git clone git@github.com:org/backend.git be
git clone git@github.com:org/frontend.git fe
wf init --name my-feature

# Work across repos
wf status                    # Branch + status per repo
wf checkout -b feat/thing    # Create branch in all repos
wf pull --rebase             # Pull all repos
wf diff                      # See changes across repos

# AI agent integration
wf agent claude              # Launch Claude Code with all repos loaded
wf agent cursor              # Open Cursor with multi-root workspace
wf context                   # Generate state snapshot for agents
```

## Installation

### Oh-my-zsh plugin (recommended)

```bash
git clone https://github.com/user/work-forest.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/work-forest
```

Add to your `.zshrc`:
```bash
plugins=(... work-forest)
```

### Manual

Add to your `.zshrc`:
```bash
source /path/to/work-forest/work-forest.plugin.zsh
```

### Homebrew

```bash
brew install user/tap/work-forest
```

## Commands

### Forest Management

| Command | Description |
|---------|-------------|
| `wf init [--name NAME] [DIR]` | Create forest.toml, auto-detect repos |
| `wf clone <url> [--as NAME] [--role ROLE]` | Clone + register in manifest |
| `wf add [DIR] [--role ROLE]` | Register existing repo |
| `wf remove <name>` | Remove from manifest (keeps files) |
| `wf list [--json]` | Table of repos with status |

### Git Operations

All git commands support `--repo NAME` to target a single repo.

| Command | Description |
|---------|-------------|
| `wf status` | Branch, dirty/clean, ahead/behind |
| `wf pull [--rebase]` | Pull across all repos |
| `wf checkout [-b] <branch>` | Checkout or create branch |
| `wf diff` | Diff summary |
| `wf rebase` | Rebase onto default branch |
| `wf stash [push\|pop]` | Stash changes |
| `wf log [N]` | Last N commits (default 3) |
| `wf fetch` | Fetch all remotes |
| `wf exec <command...>` | Run command in each repo |

### AI Agent Integration

| Command | Description |
|---------|-------------|
| `wf context` | Generate `.wf/context.md` state snapshot |
| `wf claude-md` | Generate forest-level `CLAUDE.md` |
| `wf agent claude [--prompt ".."] [--resume]` | Launch Claude Code with all repos |
| `wf agent cursor` | Open Cursor with workspace + rules |
| `wf agent codex` | Launch Codex from forest root |
| `wf open [cursor\|code\|idea]` | Open in IDE |

## forest.toml

The manifest file declares repos, their roles, and relationships:

```toml
[forest]
name = "my-feature"
description = "Feature spanning backend and frontend"
branch_pattern = "feat/{name}"

[repos.be]
url = "git@github.com:org/backend.git"
path = "be"
role = "backend"
default_branch = "master"

[repos.fe]
url = "git@github.com:org/frontend.git"
path = "fe"
role = "frontend"
default_branch = "main"

[relationships]
api_consumers = [
  { provider = "be", consumer = "fe", contract = "REST API" },
]
```

## Backward Compatibility

If you were using the `wf*` zsh functions directly, all old commands still work as aliases:

| Old | New |
|-----|-----|
| `wfstatus` | `wf status` |
| `wfpull` | `wf pull` |
| `wfcheckout` | `wf checkout` |
| `wfdiff` | `wf diff` |
| `wfrebase` | `wf rebase` |
| `wfstash` | `wf stash` |
| `wfstashpop` | `wf stash pop` |
| `wflog` | `wf log` |
| `wfexec` | `wf exec` |

## License

MIT
