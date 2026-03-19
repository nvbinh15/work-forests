# AGENTS.md — work-forest

Instructions for AI coding agents (Claude Code, Cursor, Codex, etc.) working on this project.

## Project Overview

work-forest is a zsh-based CLI tool for managing multi-repo feature workspaces ("forests"). It provides a single `wf` command that operates on all git repos in a directory, reads configuration from `forest.toml`, and generates context files for AI agents.

**Language:** Zsh (100% — no Python, Node, or compiled deps)
**Zero external dependencies** — only git and standard Unix tools (awk, sed, mktemp, basename, dirname)

## Architecture

```
bin/wf                    Standalone CLI entry point (sources lib/*, dispatches)
work-forest.plugin.zsh   Shell plugin entry point (sources lib/*, defines wf() function + aliases)
lib/_wf_toml.zsh          TOML parser (awk-based, ~80 lines)
lib/_wf_core.zsh          Core: _wf_resolve_forest, _wf_foreach, _wf_repo_paths/names
lib/_wf_git.zsh           Git commands: status, pull, checkout, diff, rebase, stash, log, fetch, exec
lib/_wf_forest.zsh        Forest management: init, clone, add, remove, list
lib/_wf_agent.zsh         AI integration: context, claude-md, agent launchers, workspace/cursorrules gen
```

### Key Patterns

- **Dispatcher pattern:** Both `bin/wf` and `work-forest.plugin.zsh` dispatch subcommands to `_wf_cmd_<name>` functions.
- **`_wf_foreach` callback:** Git operations define a `_wf_<name>_cb` callback and pass it to `_wf_foreach`, which iterates over repos (from manifest or by scanning `.git` subdirs).
- **Forest resolution:** `_wf_resolve_forest` walks up from `$PWD` to find `forest.toml`; falls back to current dir.
- **TOML parser:** `_wf_toml_parse` outputs flat `dotted.key=value` lines; other functions grep/filter them.

## Zsh Pitfalls (IMPORTANT)

These caused real bugs during development — avoid them:

1. **`local` inside loops:** In zsh, `local var=$(cmd)` inside a `for` loop that is inside a `{ } > file` redirect block will leak the assignment to stdout. **Fix:** Declare all locals before the loop, then assign without `local`.

2. **`status` is read-only:** Zsh reserves `$status` (alias for `$?`). Never use `local status=...`. Use `repo_status` or similar instead.

3. **`set -e` and fallback returns:** `_wf_resolve_forest` returns exit code 1 when no `forest.toml` is found (fallback mode). Callers using `set -e` must do `result=$(_wf_resolve_forest) || true`.

4. **Dynamic scoping:** Zsh functions use dynamic scoping — inner functions can see outer function locals. But nested function *definitions* (function inside function) can cause variable leaking issues. Prefer flat iteration over nested function callbacks for data processing.

## Testing

```bash
# Run all tests
make test

# Or individually
zsh tests/test_toml.zsh
zsh tests/test_core.zsh
zsh tests/test_git.zsh
zsh tests/test_forest.zsh
zsh tests/test_agent.zsh
zsh tests/test_integration.zsh
```

Tests create temporary git repos in `/tmp` and clean up after themselves. No network access required. No real repos are modified.

### Test conventions

- Each test file sources the needed `lib/*.zsh` files directly.
- Tests use `set -e` and fail fast with `{ echo "FAIL: ..."; exit 1; }`.
- Temp directories use `mktemp -d` with a `trap "rm -rf ..." EXIT`.
- Test names start with `Test:` for grep-ability.
- Print `PASS` per test, summary at end.

## Common Tasks

### Adding a new subcommand

1. Create `_wf_cmd_<name>()` in the appropriate `lib/_wf_*.zsh` file.
2. Add the dispatch entry in both `bin/wf` (`_wf_dispatch`) and `work-forest.plugin.zsh` (`wf()`).
3. Add completion entry in `completions/_wf`.
4. Add a test in the appropriate `tests/test_*.zsh`.
5. Update `_wf_cmd_help` in `bin/wf`.

### Adding a new git operation

1. Add `_wf_cmd_<name>()` to `lib/_wf_git.zsh` following the existing pattern:
   - Parse `--repo` flag for single-repo targeting.
   - Define a `_wf_<name>_cb` callback.
   - Call `_wf_foreach [--repo "$filter"] callback`.
2. Add dispatch + completion + test entries as above.

### Modifying the TOML parser

The parser is intentionally minimal — it handles `[table]`, `[table.subtable]`, `key = "value"` (quoted strings), and unquoted values. It does NOT handle:
- Inline tables `{ key = "val" }`
- Multi-line strings
- Arrays `[1, 2, 3]`
- Nested inline arrays

If you need these, extend `_wf_toml_parse` in `lib/_wf_toml.zsh` — keep it awk-based and zero-dep.

## Code Style

- Function names: `_wf_cmd_<subcommand>` for commands, `_wf_<name>` for internal helpers.
- Use `print -P "%F{color}text%f"` for colored output (zsh prompt escapes).
- Use `[[ ]]` not `[ ]` for conditionals.
- Quote all variable expansions: `"$var"` not `$var`.
- Prefer `$(command)` over backticks.
- Keep functions under 60 lines where possible.

## File Generation

Several commands generate files. These are ephemeral and gitignored:

| File | Generator | Purpose |
|------|-----------|---------|
| `.wf/context.md` | `wf context` | State snapshot for agents |
| `CLAUDE.md` | `wf claude-md` | Forest-level Claude Code context |
| `.cursorrules` | `wf agent cursor` / `wf open cursor` | Cursor AI rules |
| `.wf/forest.code-workspace` | `wf agent cursor` / `wf open` | VS Code multi-root workspace |

The only file meant to be committed/shared is `forest.toml`.
