# jj VCS Agent Skill

An Agent Skill that empowers AI coding assistants (Claude Code, Antigravity, and other compatible agents) to work reliably, safely, and effectively with the [Jujutsu (jj)](https://github.com/jj-vcs/jj) version control system.

## Overview

Working with Jujutsu in automated or agentic coding environments requires specific patterns to avoid interactive hangs, accidental commit pollution, or tree corruption. This skill equips agents with:

- **Agent-Safe Execution**: Non-interactive command patterns that bypass pagers, external diff formatters, and interactive editors.
- **Describe-First Philosophy**: Proper workflow for creating atomic, well-documented changes with title/body formatting.
- **State Protection**: Automatic advancement to clean working-copy commits (`jj new`) to safeguard completed revisions from accidental mutation.
- **Robust Tree Manipulation**: Stack rebasing, revision parallelization, targeted squashing, and disaster recovery via the operation log.

## Compatibility

**Tested with:** `jj v0.47.1`

This skill is designed for `jj v0.47.1` (workspace colocation flags, `jj workspace remove`, `jj file delete`, and cross-workspace `jj undo`/`jj redo` require `0.46.0+`; `revsets.git-sign-on-push` requires `0.47.1+`).

## Key Skill Features & Agent Guardrails

### 1. Automated Environment Safeguards
- **Pager & Subcommand Isolation**: Mandates `--no-pager`, `--color=never`, and explicit subcommands (`jj --no-pager --color=never status`, `jj --no-pager --color=never log`) to prevent hangs, bypass user-configured `ui.default-command`, and override `ui.color = "always"`.
- **Clean Unified Diffs**: Enforces `jj --no-pager --color=never diff --git`, `jj --no-pager --color=never interdiff --git`, `jj --no-pager --color=never show --git`, `jj --no-pager --color=never op diff --git`, and `--git` whenever `-p`/`--patch` is passed (`log -p --git`, `evolog -p --git`, `op show -p --git`) to override custom external diff tools (e.g. Difftastic, Delta) and line-number side-by-side output.
- **Non-Interactive Inputs**: Uses inline `-m` flags (including chained `-m` flags and `-m="- ..."` for hyphen-prefixed bullet paragraphs) to avoid editor prompts.
- **No Interactive Flags or TUIs**: Strictly avoids `-i` / `--interactive` across all subcommands (`squash`, `split`, `diff`, `diffedit`, `restore`, `absorb`) as well as interactive TUI/editor subcommands (`jj arrange`, `jj file edit`, `jj config edit`, `jj resolve`).
- **Detached HEAD Guardrail**: Explicitly prevents agents from running `git checkout/switch` in response to benign detached HEAD warnings in colocated repos.
- **Strict Immutability**: Prohibits `--ignore-immutable` and enforces branching off protected heads (`main`, trunk, remote tracking) via `jj new <base>`.

#### Non-Interactive Commit Splitting Recipe
Whole files can be split without an editor: `jj split -r <target> -m "Selected change message" path/to/file`. Omitting the fileset opens a diff editor, and as of jj 0.46.0 omitting `-m` opens a description editor. Splits inside a single file still use this deterministic alternative:

```bash
# 1. Create first revision off target's parent
jj new <target>- -m "First atomic change"

# 2. Restore only the files for the first commit from target
jj restore --from <target> path/to/file1.txt path/to/file2.txt

# 3. Create second revision
jj new -m "Second atomic change"

# 4. Restore remaining files from target
jj restore --from <target> path/to/file3.txt

# 5. Rebase original descendants of <target> onto the new split tip (@)
jj rebase -s '<target>+' --onto @

# 6. Verify that the reconstructed tip has exactly the target's final tree
jj --no-pager --color=never diff --from <target> --to @ --git

# 7. Run relevant test suite against reconstructed stack
# <project-specific test command>

# 8. Abandon the original target only after tree diff is empty and tests pass
jj abandon <target>

# 9. Verify rewritten stack and working copy
jj --no-pager --color=never log -r '@::'
jj --no-pager --color=never status
```

### 2. State & Commit Protection (`@` vs `@-` & `jj new`)
- **Mental Model**: Clarifies the `@` vs `@-` location rule when using `jj desc` vs `jj commit -m "..."`.
- **Always Park on a Fresh Revision**: Mandates that agents run `jj new` upon completing a task or revision, ensuring `@` is never left on the finished commit where subsequent operations or manual CLI commands could silently mutate it.

| Workflow Pattern | Where Your Labeled Commit Is | Bookmark / Push Target |
| :--- | :--- | :--- |
| `jj desc -m "..."` (before `jj new`) | `@` | `-r @` |
| `jj commit -m "..."` | `@-` (new empty `@` is created) | `-r @-` |
| `jj desc -m "..."` then `jj new` | `@-` (new empty `@` is created) | `-r @-` |
| Subagent workspace (`<ws>`) after `jj commit` / `jj new` | `<ws>@-` (`<ws>@` is empty) | `-r <ws>@-` |

### 3. Multi-Agent Workspace Orchestration Playbook
- **Isolated Workspaces**: Complete playbook for spawning $N$ parallel subagents in separate `jj workspace` instances.
- **Trusted Workspace Location**: Create workspaces under `.jj-workspaces/` inside the coordinator's launch directory, not in sibling directories. Agent tools trust the launch directory tree, so parallel agents avoid per-file permission prompts in Claude Code, Cursor, Antigravity, and similar tools without any tool-specific configuration. jj does not snapshot nested workspaces into the parent; ignore `.jj-workspaces/` globally (`core.excludesFile`) or in `.git/info/exclude` for Git-side tools.
- **`jj -R` Without Stateless `cd` Chaining**: Subagents pass `-R .jj-workspaces/<agent>` on every `jj` command instead of `cd ... && jj ...`, staying inside `Bash(jj *)` and preventing accidental mutations of the coordinator root across stateless tool calls.
- **Base Pinning & Resilient `<pinned>..<ws>@ & ~empty()` Revsets**: Read the trunk commit id with `jj --no-pager --color=never log -r main -T 'commit_id' --no-graph` and pass that literal to `jj workspace add --revision`. Coordinator merge-back uses `<pinned-commit-id>..<ws>@ & ~empty()` to select all non-empty subagent commits (whether 1 or $N$ commits, with or without trailing `jj new`), supports optional pre-merge integration testing via a temporary megamerge, and rebases into either a single local linear stack or separate PR branches.
- **Sparse Checkouts (`jj sparse`)**: Restrict workspaces to relevant subdirectories to reduce disk footprint and index times:
  ```bash
  jj sparse set --clear --add src/ --add packages/backend/
  ```
- **Agent Contracts & Scopes**: Clear rules for agent prompt contracts, directory scoping, pre-flight workspace checks, and merge-back workflows (`jj diff --stat`, local stack or multi-branch rebasing, and cleanup with `jj workspace remove`).

### 4. Idempotent Bookmark & Branch Management
- **Safe Bookmark Updates**: Recommends `jj bookmark set <name> -r <target>` (which creates or moves bookmarks idempotently without erroring).
- **Bookmark Renaming**: Rename existing bookmarks cleanly with `jj bookmark rename <old> <new>`.
- **Remote Tracking**: Explicit `track` and `untrack` commands for syncing remote bookmark references:
  ```bash
  jj bookmark track feat-x@origin
  jj bookmark untrack feat-x@origin
  ```
- **Bookmark Advancing**: Covers built-in `jj bookmark advance` to slide bookmarks forward along stacks.
- **Push Previews & Targets**: Encourages dry-run previews and explicit remote/change-id push targets:
  ```bash
  jj git push --dry-run -b <name>
  jj git push --bookmark <name> --remote origin
  jj git push -c <change-id>
  ```

### 5. Advanced Tree Manipulation & Megamerges
- **Targeted Squashing**: Move changes directly into/from specific revisions without full rebases (`jj squash --into <id>`, `jj squash --from <id>`, `-u`).
- **Parallelizing Commits**: Convert sequential, orthogonal commits into parallel sibling branches off a common parent with `jj parallelize`.
- **Targeted Absorption**: Absorb changes into ancestor commits automatically (`jj absorb`) or restrict absorption to specific paths (`jj absorb path/to/file`), then verify with `jj --no-pager --color=never op show -p --git`.
- **Duplicating & Reverting Revisions (`jj duplicate`, `jj revert`)**: Create independent sibling copies of changes with fresh Change IDs (`jj duplicate <change-id>`) or apply reverse-diff commits (`jj revert -r <change-id> --onto @`):
  ```bash
  jj duplicate <change-id>
  jj revert -r <change-id> --onto @
  ```
- **Stack Rebasing**: Idiomatic branch and stack rebasing onto trunk with `jj rebase -b @ --onto main` and roots revsets.
- **Megamerges for Testing**: Create local octopus merges (`jj new feat-a feat-b feat-c`) to compile, test, and verify multiple in-flight features together without pushing the merge commit.

### 6. Multi-Step Disaster Recovery
- **Operation Log Rollback, Single-Op Revert & Non-Destructive Preview**: Preview prior repository state via `jj --no-pager --color=never status --at-op=<operation-id>` or `log --at-op=<operation-id>`, revert a single earlier operation with `jj op revert <operation-id>`, or restore full repository state with `jj op restore <operation-id>` alongside `jj undo` / `jj redo`.

### 7. Historical Inspection & Scripting Recipes
- **Machine-Readable Scripting (`-T` / `--template`)**: Query `change_id`, `commit_id`, `empty`, `conflict`, `immutable`, and one-line summaries without graph pollution or regex parsing:
  ```bash
  jj --no-pager --color=never log -r @ -T 'change_id' --no-graph
  jj --no-pager --color=never log -r @ -T 'commit_id' --no-graph
  jj --no-pager --color=never log -r @ -T 'empty' --no-graph
  jj --no-pager --color=never log -r @ -T 'conflict' --no-graph
  jj --no-pager --color=never log -r 'trunk()..@' --no-graph -T 'change_id.shortest(8) ++ " " ++ description.first_line() ++ "\n"'
  ```
- **Configuration Inspection**: Query active settings without opening editors:
  ```bash
  jj --no-pager --color=never config list
  jj --no-pager --color=never config get user.name
  ```
- **Git Hooks & `jj fix` Awareness**: Jujutsu snapshots work continuously without triggering Git `pre-commit` hooks. Agents must run linters, formatters, and tests directly before finishing work (or use `jj fix -s 'roots(trunk()..@)'` when `fix.tools` is configured).
- **Filesets, Historical Search & Local Ignore**: Query tracked files, read or search historical file contents (`jj --no-pager --color=never file show`, `jj --no-pager --color=never file search`), scope path expressions with filesets (`'glob:"**/*.ts"'`, `'src/ & ~src/generated/'`), and manage untracked agent artifacts via `.jj/ignore`.
- **Diagnostic Revsets**: Ready-to-use cheat sheet for stack queries (`trunk()..@`, `heads()`, `roots()`), merge conflicts (`conflicts()`), divergent revisions (`divergent()`), unpushed changes (`remote_bookmarks()..`), and empty mutable commit cleanup:
  ```bash
  # Abandon empty mutable commits (excluding root and @)
  jj abandon 'empty() & mutable() & ~root() & ~@'
  ```

### 8. Optional `PreToolUse` Guardrail Hook (`scripts/check-jj-cmd.sh`)
- Bundles a fast, token-aware guardrail script (`jujutsu/scripts/check-jj-cmd.sh`) that deterministically blocks interactive flags (`-i`, `--interactive`, `--editor`, `--tool`), TUI/editor/merge commands (`jj arrange`, `jj file edit`, `jj config edit`, `jj resolve`, bare `jj desc`/`commit`/`ci`/`squash`/`converge`/`git push`, incomplete `jj revert`), unescaped hyphen-prefixed `-m "- ..."` arguments, forbidden flags (`--ignore-immutable`, `--allow-cross-workspace`), compound shell operators (`&&`, `||`, `|`, `$()`), and output/diff commands missing `--no-pager --color=never` or `--git`/`--stat` (including `-p`/`--patch` and `op diff`).
- Works out of the box with both **Claude Code** (`~/.claude/settings.json`) and **Antigravity** (`~/.gemini/config/hooks.json` or `.agents/hooks.json`):

```json
// Claude Code (~/.claude/settings.json)
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/jujutsu/scripts/check-jj-cmd.sh"
          }
        ]
      }
    ]
  }
}
```

```json
// Antigravity (~/.gemini/config/hooks.json or .agents/hooks.json)
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {
            "type": "command",
            "command": "~/.gemini/config/skills/jujutsu/scripts/check-jj-cmd.sh"
          }
        ]
      }
    ]
  }
}
```

## Installation

### Using `just`

If you use [just](https://just.systems), run:

```bash
# Install globally for all supported assistants (Claude Code & Antigravity)
just install

# Or install for a specific assistant
just install-claude
just install-antigravity

# Install locally in the current project workspace
just install-local
just install-local-claude
just install-local-antigravity

# Clean up / uninstall skill directories
just uninstall
just uninstall-local

# Verify doc patterns, hook test suite, and sync status
just check
just check-patterns
just check-hook
just check-sync
```

### Manual Installation

#### Claude Code

Install globally:

```bash
mkdir -p ~/.claude/skills/jujutsu
cp -R ./jujutsu/. ~/.claude/skills/jujutsu/
```

Or install locally in a specific project:

```bash
mkdir -p .claude/skills/jujutsu
cp -R ./jujutsu/. .claude/skills/jujutsu/
```

#### Antigravity / Gemini CLI

Install globally:

```bash
mkdir -p ~/.gemini/config/skills/jujutsu ~/.gemini/skills/jujutsu
cp -R ./jujutsu/. ~/.gemini/config/skills/jujutsu/
cp -R ./jujutsu/. ~/.gemini/skills/jujutsu/
```

Or install locally in a specific workspace:

```bash
mkdir -p .agents/skills/jujutsu
cp -R ./jujutsu/. .agents/skills/jujutsu/
```

*(Note: `.gemini/skills/jujutsu/` is also supported as an alternate workspace path).*

## Skill Contents

```
jujutsu/
├── SKILL.md                  # Complete jj agent workflow instructions and quick reference
└── scripts/
    └── check-jj-cmd.sh       # Optional PreToolUse guardrail hook for Claude Code & Antigravity
```

## Contributing

Contributions are welcome. Please ensure any changes are compatible with `jj v0.47.1` and follow agent-safe non-interactive practices.

## License

MIT
