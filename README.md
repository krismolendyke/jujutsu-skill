# jj VCS Agent Skill

An Agent Skill that empowers AI coding assistants (Claude Code, Antigravity, and other compatible agents) to work reliably, safely, and effectively with the [Jujutsu (jj)](https://github.com/jj-vcs/jj) version control system.

## Overview

Working with Jujutsu in automated or agentic coding environments requires specific patterns to avoid interactive hangs, accidental commit pollution, or tree corruption. This skill equips agents with:

- **Agent-Safe Execution**: Non-interactive command patterns that bypass pagers, external diff formatters, and interactive editors.
- **Describe-First Philosophy**: Proper workflow for creating atomic, well-documented changes with title/body formatting.
- **State Protection**: Automatic advancement to clean working-copy commits (`jj new`) to safeguard completed revisions from accidental mutation.
- **Robust Tree Manipulation**: Stack rebasing, revision parallelization, targeted squashing, and disaster recovery via the operation log.

## Compatibility

**Tested with:** `jj v0.44.0`

This skill is designed for `jj v0.44.0` and may work with other versions, though compatibility is not guaranteed.

## Key Skill Features & Agent Guardrails

### 1. Automated Environment Safeguards
- **Pager & Subcommand Isolation**: Mandates `--no-pager` and explicit subcommands to prevent hangs and bypass user-configured `ui.default-command`.
- **Clean Unified Diffs**: Enforces `jj --no-pager diff --git` to override custom external diff tools (e.g. Difftastic, Delta) and line-number side-by-side output.
- **Non-Interactive Inputs**: Uses inline `-m` flags (including chained `-m` flags for structured title and body paragraphs) to avoid editor prompts.
- **Strict Immutability**: Prohibits `--ignore-immutable` and enforces branching off protected heads (`main`, trunk, remote tracking) via `jj new <base>`.

### 2. State & Commit Protection (`@` vs `@-` & `jj new`)
- **Mental Model**: Clarifies the `@` vs `@-` location rule when using `jj desc` vs `jj commit -m "..."`.
- **Always Park on a Fresh Revision**: Mandates that agents run `jj new` upon completing a task or revision, ensuring `@` is never left on the finished commit where subsequent operations or manual CLI commands could silently mutate it.

### 3. Multi-Agent Workspace Orchestration Playbook
- **Isolated Workspaces**: Complete playbook for spawning $N$ parallel subagents in separate `jj workspace` instances.
- **Base Pinning**: Pins exact base commit hashes (`BASE=$(jj log -r main -T 'commit_id' --no-graph)`) to ensure parallel sibling branches.
- **Agent Contracts & Scopes**: Clear rules for agent prompt contracts, directory scoping, and merge-back workflows (`jj diff --stat`, serial rebasing, and cleanup).

### 4. Idempotent Bookmark & Branch Management
- **Safe Bookmark Updates**: Recommends `jj bookmark set <name> -r <target>` (which creates or moves bookmarks idempotently without erroring).
- **Bookmark Advancing**: Covers built-in `jj bookmark advance` to slide bookmarks forward along stacks.
- **Push Previews**: Encourages `jj git push --dry-run -b <name>` to inspect remote modifications before pushing.

### 5. Advanced Tree Manipulation & Megamerges
- **Targeted Squashing**: Move changes directly into/from specific revisions without full rebases (`jj squash --into <id>`, `jj squash --from <id>`, `-u`).
- **Parallelizing Commits**: Convert sequential, orthogonal commits into parallel sibling branches off a common parent with `jj parallelize`.
- **Stack Rebasing**: Idiomatic branch and stack rebasing onto trunk with `jj rebase -b @ -d main` and roots revsets.
- **Megamerges for Testing**: Create local octopus merges (`jj new feat-a feat-b feat-c`) to compile, test, and verify multiple in-flight features together without pushing the merge commit.

### 6. Multi-Step Disaster Recovery
- **Operation Log Rollback**: Instant repository restoration to any prior state using `jj --no-pager op log` and `jj op restore <operation-id>` alongside `jj undo` / `jj redo`.

### 7. Historical Inspection & Revset Recipes
- **File Inspection**: Query tracked files and read historical contents directly from stdout (`jj file list -r <id>`, `jj file show -r <id> <path>`).
- **Diagnostic Revsets**: Ready-to-use cheat sheet for stack queries (`trunk()..@`, `heads()`, `roots()`), merge conflicts (`conflicts()`), divergent revisions (`divergent()`), and empty commit cleanup.

## Installation

### Using `just`

If you use [just](https://just.systems), run:

```bash
# Install globally for all supported assistants (Claude Code & Antigravity)
just install

# Or install for a specific assistant
just install-claude
just install-antigravity
```

### Manual Installation

#### Claude Code

Install globally:

```bash
mkdir -p ~/.claude/skills
cp -r jujutsu/ ~/.claude/skills/jujutsu/
```

Or install locally in a specific project:

```bash
mkdir -p .claude/skills
cp -r jujutsu/ .claude/skills/jujutsu/
```

#### Antigravity / Gemini CLI

Install globally:

```bash
mkdir -p ~/.gemini/config/skills
cp -r jujutsu/ ~/.gemini/config/skills/jujutsu/
```

Or install locally in a specific workspace:

```bash
mkdir -p .gemini/skills
cp -r jujutsu/ .gemini/skills/jujutsu/
```

## Skill Contents

```
jujutsu/
└── SKILL.md    # Complete jj agent workflow instructions and quick reference
```

## Contributing

Contributions are welcome. Please ensure any changes are compatible with `jj v0.44.0` and follow agent-safe non-interactive practices.

## License

MIT
