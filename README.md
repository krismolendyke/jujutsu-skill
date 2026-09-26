# jj VCS Agent Skill

An Agent Skill that empowers AI coding assistants (Claude Code, Antigravity, and other compatible agents) to work reliably, safely, and effectively with the [Jujutsu (jj)](https://github.com/jj-vcs/jj) version control system.

## Overview

Working with Jujutsu in automated or agentic coding environments requires specific patterns to avoid interactive hangs, accidental commit pollution, or tree corruption. This skill equips agents with:

- **Agent-Safe Execution**: Non-interactive command patterns that bypass pagers, external diff formatters, and interactive editors.
- **Describe-First Philosophy**: Proper workflow for creating atomic, well-documented changes with title/body formatting.
- **State Protection**: Automatic advancement to clean working-copy commits (`jj new`) to safeguard completed revisions from accidental mutation.
- **Robust Tree Manipulation**: Stack rebasing, revision parallelization, targeted squashing, and disaster recovery via the operation log.

## Compatibility

**Tested with:** `jj v0.45.1` (compatible with `jj v0.44.0` - `v0.45.1`)

This skill is designed for `jj v0.45.1` (and `v0.44.0+`) and may work with other versions, though compatibility is not guaranteed.

## Key Skill Features & Agent Guardrails

### 1. Automated Environment Safeguards
- **Pager & Subcommand Isolation**: Mandates `--no-pager` and explicit subcommands (`jj --no-pager status`, `jj --no-pager log`) to prevent hangs and bypass user-configured `ui.default-command`.
- **Clean Unified Diffs**: Enforces `jj --no-pager diff --git`, `jj --no-pager interdiff --git`, and `jj --no-pager show --git` to override custom external diff tools (e.g. Difftastic, Delta) and line-number side-by-side output.
- **Non-Interactive Inputs**: Uses inline `-m` flags (including chained `-m` flags for structured title and body paragraphs) to avoid editor prompts.
- **No Interactive Flags**: Strictly avoids `-i` / `--interactive` across all subcommands (`squash`, `split`, `diff`, `diffedit`, `restore`, `absorb`).
- **Detached HEAD Guardrail**: Explicitly prevents agents from running `git checkout/switch` in response to benign detached HEAD warnings in colocated repos.
- **Strict Immutability**: Prohibits `--ignore-immutable` and enforces branching off protected heads (`main`, trunk, remote tracking) via `jj new <base>`.

#### Non-Interactive Commit Splitting Recipe
`jj split` opens an interactive UI that hangs automated agents. The skill provides a deterministic, verified non-interactive alternative:

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
jj --no-pager diff --from <target> --to @ --git

# 7. Run relevant test suite against reconstructed stack
# <project-specific test command>

# 8. Abandon the original target only after tree diff is empty and tests pass
jj abandon <target>

# 9. Verify rewritten stack and working copy
jj --no-pager log -r '@::'
jj --no-pager status
```

### 2. State & Commit Protection (`@` vs `@-` & `jj new`)
- **Mental Model**: Clarifies the `@` vs `@-` location rule when using `jj desc` vs `jj commit -m "..."`.
- **Always Park on a Fresh Revision**: Mandates that agents run `jj new` upon completing a task or revision, ensuring `@` is never left on the finished commit where subsequent operations or manual CLI commands could silently mutate it.

| Workflow Pattern | Where Your Labeled Commit Is | Bookmark / Push Target |
| :--- | :--- | :--- |
| `jj desc -m "..."` (before `jj new`) | `@` | `-r @` |
| `jj commit -m "..."` | `@-` (new empty `@` is created) | `-r @-` |
| `jj desc -m "..."` then `jj new` | `@-` (new empty `@` is created) | `-r @-` |

### 3. Multi-Agent Workspace Orchestration Playbook
- **Isolated Workspaces**: Complete playbook for spawning $N$ parallel subagents in separate `jj workspace` instances.
- **Base Pinning**: Pins exact base commit hashes (`BASE=$(jj log -r main -T 'commit_id' --no-graph)`) to ensure parallel sibling branches.
- **Sparse Checkouts (`jj sparse`)**: Restrict workspaces to relevant subdirectories to reduce disk footprint and index times:
  ```bash
  jj sparse set --clear --add src/ --add packages/backend/
  ```
- **Agent Contracts & Scopes**: Clear rules for agent prompt contracts, directory scoping, and merge-back workflows (`jj diff --stat`, serial rebasing, and cleanup).

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
- **Targeted Absorption**: Absorb changes into ancestor commits automatically (`jj absorb`) or restrict absorption to specific paths (`jj absorb path/to/file`), then verify with `jj --no-pager op show -p`.
- **Duplicating Revisions (`jj duplicate`)**: Create independent sibling copies of changes with fresh Change IDs for experimental spikes and refactoring spikes:
  ```bash
  jj duplicate <change-id>
  ```
- **Stack Rebasing**: Idiomatic branch and stack rebasing onto trunk with `jj rebase -b @ --onto main` and roots revsets.
- **Megamerges for Testing**: Create local octopus merges (`jj new feat-a feat-b feat-c`) to compile, test, and verify multiple in-flight features together without pushing the merge commit.

### 6. Multi-Step Disaster Recovery
- **Operation Log Rollback**: Instant repository restoration to any prior state using `jj --no-pager op log` and `jj op restore <operation-id>` alongside `jj undo` / `jj redo`.

### 7. Historical Inspection & Scripting Recipes
- **Machine-Readable Scripting (`-T` / `--template`)**: Query `change_id`, `commit_id`, `empty`, `conflict`, and `immutable` without graph pollution or regex parsing:
  ```bash
  CHANGE_ID=$(jj log -r @ -T 'change_id' --no-graph)
  COMMIT_ID=$(jj log -r @ -T 'commit_id' --no-graph)
  IS_EMPTY=$(jj log -r @ -T 'empty' --no-graph)
  HAS_CONFLICTS=$(jj log -r @ -T 'conflict' --no-graph)
  ```
- **Git Hooks Awareness**: Jujutsu snapshots work continuously without triggering Git `pre-commit` hooks. Agents must run linters, formatters, and tests directly before finishing work.
- **File Inspection & Local Ignore**: Query tracked files, read historical file contents (`jj --no-pager file show`), and manage untracked agent artifacts via `.jj/ignore`.
- **Diagnostic Revsets**: Ready-to-use cheat sheet for stack queries (`trunk()..@`, `heads()`, `roots()`), merge conflicts (`conflicts()`), divergent revisions (`divergent()`), unpushed changes (`remote_bookmarks()..`), and empty mutable commit cleanup:
  ```bash
  # Abandon empty mutable commits (excluding root and @)
  jj abandon 'empty() & mutable() & ~root() & ~@'
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

# Clean up / uninstall global skill directories
just uninstall
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
mkdir -p ~/.gemini/config/skills/jujutsu
cp -R ./jujutsu/. ~/.gemini/config/skills/jujutsu/
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
└── SKILL.md    # Complete jj agent workflow instructions and quick reference
```

## Contributing

Contributions are welcome. Please ensure any changes are compatible with `jj v0.45.1` and follow agent-safe non-interactive practices.

## License

MIT
