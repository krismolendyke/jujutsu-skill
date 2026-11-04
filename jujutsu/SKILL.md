---
name: jujutsu
description: "**REQUIRED** - Always activate FIRST on any git/VCS operations (commit, status, branch, push, etc.), especially when HEAD is detached. If `.jj/` exists -> this is a Jujutsu (jj) repo - raw git commands can corrupt data. Essential git safety instructions inside. DO NOT IGNORE."
allowed-tools: Bash(jj *)
---

# Jujutsu (jj) Version Control System

This skill helps you work with Jujutsu, a Git-compatible VCS with mutable commits and automatic rebasing.

**Tested with jj v0.46.0.** Commands may differ in other versions. `jj workspace add --colocate`/`--no-colocate`, `jj workspace remove`, `jj file delete`, and `jj undo --allow-cross-workspace` require 0.46.0.

## Important: Automated/Agent Environment

When running as an agent:

1. **Always use `--no-pager`, `--color=never`, and explicit subcommands**: Never invoke bare `jj` (which triggers user-configured `ui.default-command`). Always pass explicit subcommands, `--no-pager`, and `--color=never`. `--no-pager` keeps commands from opening an interactive pager (like `less`), which will hang the agent. `--color=never` overrides `ui.color = "always"` so captured output is not wrapped in ANSI codes. Do not rely on `NO_COLOR`; it is not set in every environment.

```bash
# Always use --no-pager and --color=never on commands that query status or produce output
jj --no-pager --color=never status             # NOT: bare jj status or jj st (can open pager)
jj --no-pager --color=never log                # NOT: jj log or bare jj
jj --no-pager --color=never diff --git         # NOT: jj diff (always include --git)
jj --no-pager --color=never interdiff --from <old-revision> --to <new-revision> --git
jj --no-pager --color=never show --git <id>    # NOT: jj show <id> (always include --git)
jj --no-pager --color=never <cmd> --help       # NOT: jj <cmd> --help (can open pager)
```

2. **Always use `-m` flags** to provide messages inline rather than relying on editor prompts:

```bash
# Always use -m to avoid editor prompts
jj desc -m "message"      # NOT: jj desc
jj squash -m "message"    # NOT: jj squash (which opens editor)
```

Editor-based commands will fail in non-interactive environments.

3. **Never use `-i` or `--interactive` flags**: Subcommands like `squash -i`, `diff -i`, `diffedit`, `restore -i`, `absorb -i`, and `jj file edit` launch interactive terminal prompts or editors that will hang automated agents. `jj split` does too unless you pass both a fileset and `-m` (and do not pass `--editor`). Always use non-interactive flags or explicit path arguments.

4. **Verify operations after mutations** (`squash`, `abandon`, `rebase`, `restore`). Run `jj --no-pager --color=never status`, inspect the affected graph with `jj --no-pager --color=never log`, and check relevant content invariants; a successful exit alone does not prove that the intended changes were preserved.

5. **Never run `git checkout`/`git switch` to "fix" detached HEAD**: In colocated repos (`.jj/` + `.git/`), Git HEAD is intentionally detached to point at jj's `@` or `@-`. Linters or tools reporting "detached HEAD" are encountering normal jj operation. Do not attempt to checkout git branches.

6. **Always finish by creating a new empty commit (`jj new`)**: Never leave the working copy (`@`) pointing to a completed commit. When you are done with your task or changes, always run `jj new` to move to a fresh, empty commit so subsequent agent actions or CLI commands do not accidentally modify the completed revision.

7. **NEVER use or suggest `--ignore-immutable`**: Immutable commits (such as `main`, `trunk()`, or remote branches) are strictly protected. If an operation fails with a `Commit <id> is immutable` error, **do NOT attempt to bypass it with `--ignore-immutable`**. Instead, create a new change on top of the immutable commit using `jj new <base>` or rebase your mutable commits onto it.

8. **Stay within the declared command boundary**: This skill grants `Bash(jj *)`, not unrestricted shell or Git access. Do not wrap `jj` in a shell assignment (`NAME=$(jj ...)`), prefix it with `cd <dir> && jj ...`, chain commands with `&&`, `||`, or `;`, or pipe output (`| head`, `| grep`). Compound shell commands do not match `Bash(jj *)` and trigger permission prompts. Instead:
   - Read values from `jj` output and pass them back as literals, or use revsets directly.
   - Target another workspace with `jj -R <workspace-path> ...` instead of `cd <workspace-path> && jj ...`.
   - Use `jj commit -m "..."` (or separate tool calls) instead of `jj desc -m "..." && jj new`.
   - Limit output with `jj log -n <N>`, `-r`, or `-T` instead of piping to `head` or `grep`.

9. **Do not disable signing**: If a command fails with an SSH sign or 1Password error (`op-ssh-sign`, "Could not connect to socket"), stop and report it. Do not pass `--config` to change `signing.behavior`, and do not retry with signing turned off. Some configs sign at push time (`signing.behavior = "drop"` and `git.sign-on-push = true`); leave that alone too.

*(Optional Guardrail Hook: [`./scripts/check-jj-cmd.sh`](./scripts/check-jj-cmd.sh) can be wired into Claude Code or Antigravity `PreToolUse` hooks to deterministically block interactive flags, missing `--no-pager --color=never`, or forbidden flags before execution).*

## Core Concepts

### The Working Copy is a Commit (`@` vs `@-`)

In jj, your working directory is always a commit (referenced as `@`). Changes are automatically snapshotted when you run any jj command. There is no staging area.

- **`jj desc -m "..."`**: Labels the current working-copy commit `@`.
- **`jj new`**: Creates a fresh, empty commit on top of `@` (the previous commit becomes `@-`).
- **`jj commit -m "..."`**: One-step shortcut that describes `@` and advances to a new empty commit (`@` becomes `@-`).

| Workflow Pattern | Where Your Labeled Commit Is | Bookmark / Push Target |
| :--- | :--- | :--- |
| `jj desc -m "..."` (before `jj new`) | `@` | `-r @` |
| `jj commit -m "..."` | `@-` (new empty `@` is created) | `-r @-` |
| `jj desc -m "..."` then `jj new` | `@-` (new empty `@` is created) | `-r @-` |
| Subagent workspace (`<ws>`) after `jj commit` / `jj new` | `<ws>@-` (`<ws>@` is empty) | `-r <ws>@-` |

### Commits Are Mutable (Except Immutable Heads)

**CRITICAL**: Unlike git, jj commits can be freely modified after creation. You can update descriptions, squash changes, rebase, and absorb — all without creating new commits.

However, certain revisions (such as `trunk()`, `main`, or pushed remote commits) are marked as **immutable** (`immutable()` revset) to prevent altering shared history. Never rewrite immutable commits or pass `--ignore-immutable`; branch off with `jj new <base>`.

### Change IDs vs Commit IDs

- **Change ID**: A stable identifier (like `tqpwlqmp`) that persists when a commit is rewritten — prefer these when referencing commits.
- **Commit ID**: A content hash (like `3ccf7581`) that changes when commit content changes.

### Revsets

jj uses a functional revset language to query and select commits (`jj --no-pager --color=never log -r '<revset>'`):

| Intent | Revset Expression | Description |
|--------|-------------------|-------------|
| **Current Stack** | `trunk()..@` | All commits on current branch since trunk |
| **Stack Tip** | `heads(trunk()..@)` | Top-most commit of the current branch |
| **Stack Root** | `roots(trunk()..@)` | Base commit of the current branch |
| **Workspace Commit** | `<ws>@` / `<ws>@-` | Working-copy commit (or parent) of workspace `<ws>` |
| **All Workspaces** | `working_copies()` | Working-copy `@` commits across all workspaces |
| **Recent History** | `ancestors(@, 5)` | Last 5 commits leading up to `@` |
| **Unpushed Commits** | `remote_bookmarks()..` | Commits not yet pushed to any remote |
| **Conflicts** | `conflicts()` | Commits containing unresolved merge conflicts |
| **Divergent** | `divergent()` | Commits with split Change IDs (`??`) |
| **Empty Commits** | `empty() & ~root()` | Empty commits (useful for cleanup) |
| **Mutable / Immutable** | `mutable()` / `immutable()` | Rewritable vs. protected commits |
| **Bookmarks** | `bookmarks()` | Commits marked with bookmarks |

### Filesets (Path Expressions)

Path arguments in `jj` (`diff`, `restore`, `squash`, `split`, `file list`) are parsed as **filesets** (prefix/exact match by default, not shell globs). Prefix wildcard patterns with `glob:` and combine paths with `&`, `|`, and `~`:

```bash
jj --no-pager --color=never diff --git 'glob:"**/*.ts"'
jj --no-pager --color=never diff --git 'src/ & ~src/generated/'
```

### Machine-Readable Template Queries (`-T` / `--template`)

Extract commit metadata without graph characters or regex parsing by combining `-T` with `--no-graph` (read values from output and pass back as literals; never wrap `jj` in `$()`):

```bash
jj --no-pager --color=never log -r @ -T 'change_id' --no-graph
jj --no-pager --color=never log -r @ -T 'commit_id' --no-graph
jj --no-pager --color=never log -r @ -T 'empty' --no-graph        # "true" or "false"
jj --no-pager --color=never log -r @ -T 'conflict' --no-graph     # "true" or "false"
jj --no-pager --color=never log -r @ -T 'immutable' --no-graph    # "true" or "false"
jj --no-pager --color=never log -r @ -T 'description.first_line()' --no-graph
jj --no-pager --color=never log -r 'trunk()..@' --no-graph -T 'change_id.shortest(8) ++ " " ++ description.first_line() ++ "\n"'
```

## Essential Workflow

### Starting Work: Describe First, Then Code

**Always create your commit message before writing code:**

1. **Branching off trunk/main or a specific base**: Create your new revision directly off your intended base rather than stacking on an unrelated working revision:

```bash
jj new main -m "Add user authentication to login endpoint"
jj new <change-id> -m "Add validation to user input forms"
```

2. **Continuing on current branch**: Validate that `@` is empty with `jj --no-pager --color=never st`. If not empty, run `jj new` first:

```bash
jj new
jj desc -m "Add user authentication to login endpoint"
# ... edit files ...
jj --no-pager --color=never status
```

### Creating Atomic Commits & Multi-line Descriptions

Each commit should represent ONE logical change using an imperative title (e.g. `"Add validation to user input forms"`, `"Fix null pointer in payment processor"`).

To write multi-paragraph commit messages without opening an editor or risking shell escaping issues, chain multiple `-m` flags (`jj` separates each `-m` with a blank line):

```bash
jj desc \
  -m "Add OAuth2 authentication provider" \
  -m "Introduce Google and GitHub OAuth handlers with token refresh." \
  -m "- Implement callback router\n- Add token refresh middleware"
```

### Viewing History

Use `diff` to compare repository trees and `interdiff` (always with explicit `--from` and `--to`) to compare how a patch evolved across rewrites or rebases:

```bash
jj --no-pager --color=never log
jj --no-pager --color=never log -p
jj --no-pager --color=never show --git <change-id>
jj --no-pager --color=never diff --git
jj --no-pager --color=never interdiff --from <old-revision> --to <new-revision> --git
```

**Why `--git` is required on `diff`/`show`/`interdiff`**: Default `jj diff` outputs side-by-side line numbers, and user configs often set `ui.diff-formatter` to external tools (Difftastic, Delta). Passing `--git` forces a clean, unified `+`/`-` diff.

### Moving Between Commits & Finishing Work (`jj new`)

```bash
jj new                              # Create a fresh empty commit on top of @ (protects completed @-)
jj new -m "Commit message"          # Create a new commit with message on @ (does not park an empty child)
jj new main -m "New branch"         # Branch off main (or <base-change-id>)
jj edit <change-id>                 # Edit an existing mutable commit (@ becomes that commit)
jj prev -e                          # Edit parent commit
jj next -e                          # Edit child commit
```

**CRITICAL**: Because jj snapshots working-directory edits into `@` automatically, leaving `@` on a finished commit means any subsequent command or manual edit silently mutates it. Always run `jj new` (or `jj commit -m "..."`) when finishing a task so `@` is parked on a fresh, empty child commit.

## Refining Commits

### Squashing Changes

Move changes from one revision into another without having to manually rebase:

```bash
# Squash all changes from the current commit into its parent.
# -u keeps the destination description and skips the editor.
jj squash -u

# Squash changes into a specific ancestor commit
jj squash --into <change-id> -u

# Squash only specific files into an ancestor commit
jj squash --into <change-id> -u path/to/file.txt

# Pull changes from another revision into the current commit
jj squash --from <change-id> -u

# Or supply a new destination message with -m
jj squash --into <change-id> -m "Updated commit message"
```

**Note**: `jj squash -i` opens an interactive UI and will hang in agent environments. Avoid it.

### Splitting Commits (Non-Interactive Recipe)

`jj split` opens a diff editor when no filesets are given, and as of jj 0.46.0 it opens one description editor unless `-m` is set. `--editor` forces that description editor even with `-m`. Do not use either.

To move whole files into the selected commit without an editor:

```bash
jj split -r <target> -m "Selected change message" path/to/file1 path/to/file2
```

The other revision keeps its original description. For a split inside a single file, reconstruct the commits without `jj split`:

```bash
# 1. Create first revision off target's parent
jj new <target>- -m "First atomic change"

# 2. Restore only the files for the first commit from target
jj restore --from <target> path/to/file1.txt path/to/file2.txt

# 3. Create second revision
jj new -m "Second atomic change"

# 4. Restore remaining files from target
jj restore --from <target> path/to/file3.txt

# 5. Rebase every original descendant of <target> onto the new split tip (@)
jj rebase -s '<target>+' --onto @

# 6. Verify that the reconstructed tip has exactly the target's final tree
# This command must produce no diff before continuing.
jj --no-pager --color=never diff --from <target> --to @ --git

# 7. Run the project's relevant tests against the reconstructed stack
# <project-specific test command>

# 8. Only after the tree diff is empty and tests pass, abandon the original
jj abandon <target>

# 9. Verify the rewritten stack from the split tip through its descendants
jj --no-pager --color=never log -r '@::'
jj --no-pager --color=never status
```

If the tree-equivalence diff is not empty or tests fail, stop: do not abandon `<target>`. The original change still preserves the complete content. Correct the reconstructed commits, or use `jj undo` to reverse the most recent operation, then repeat verification.

### Absorbing Changes

Automatically distribute changes to the commits that last modified those lines:

```bash
# Absorb working copy changes into appropriate ancestor commits
jj absorb

# Absorb only changes to specific paths
jj absorb path/to/file.txt

# Verify what was absorbed via the operation diff
jj --no-pager --color=never op show -p
```

### Abandoning Commits

Remove a commit entirely (descendants are rebased to its parent):

```bash
# Abandon a specific commit
jj abandon <change-id>

# Clean up empty mutable commits left over from rebases or abandoned work
jj abandon 'empty() & mutable() & ~root() & ~@'
```

### Duplicating Revisions (`jj duplicate`)

Create an exact copy of an existing revision with a brand new Change ID. This is useful for exploratory refactorings, prototype spikes, or preserving a snapshot before destructive tests:

```bash
# Duplicate a specific revision (creates a sibling commit with a fresh Change ID)
jj duplicate <change-id>

# Duplicate the working commit @ or parent @-
jj duplicate @-
```

### Undoing Operations and Multi-Step Recovery

Jujutsu records every repo mutation in an append-only operation log.

```bash
# Reverse the single most recent operation in this workspace
jj undo

# Redo the most recently undone operation in this workspace
jj redo

# View recent operations (always pass --no-pager and optionally -n to limit output)
jj --no-pager --color=never op log -n 10

# Preview repository status or log at an earlier operation WITHOUT restoring
jj --no-pager --color=never status --at-op=<operation-id>
jj --no-pager --color=never log --at-op=<operation-id> -n 5

# Restore the entire repository state to a specific prior operation ID
jj op restore <operation-id>
```

Use operation-level recovery carefully: `jj op restore` restores the state of the entire repository and can undo unrelated work recorded after that operation. Preview with `--at-op` first to confirm what will be restored.

As of jj 0.46.0, `jj undo` and `jj redo` refuse an operation that was performed in another workspace. If that happens, stop and report it. Do not add `--allow-cross-workspace`; it can revert another workspace's work.

For a targeted view of how one change evolved across rewrites, inspect its evolution log:

```bash
jj --no-pager --color=never evolog -p -r <change-id>
```

Use the displayed commit IDs to inspect an earlier version with `jj --no-pager --color=never show --git <commit-id>` or build a new change from one with `jj new <commit-id>`. Prefer this targeted approach when unrelated repository work must remain intact.

### Rebasing Commits

Move commits to a different parent. Prefer `--onto` (or `-o`); `-d`/`--destination` remains a supported alias.

```bash
# Rebase the entire current stack/branch onto main (common update workflow)
jj rebase --onto main
# Or explicitly by branch/stack:
jj rebase -b @ --onto main

# Rebase a specific revision and all its descendants onto a destination
jj rebase -s <change-id> --onto <destination>

# Rebase a whole stack using roots revset
jj rebase -s 'roots(trunk()..@)' --onto main

# Rebase ONLY a single revision (rebasing its descendants onto its parents)
jj rebase -r <change-id> --onto <destination>

# Insert a commit before or after another revision
jj rebase -r <change-id> -A <target-commit>   # insert after target
jj rebase -r <change-id> -B <target-commit>   # insert before target
```

### Parallelizing Revisions (`jj parallelize`)

When multiple changes in a linear stack are independent and do not depend on each other, make them sibling branches off their shared parent:

```bash
# Convert sequential revisions into parallel siblings off their common base
jj parallelize <change-A> <change-B>

# Parallelize all commits in current stack
jj parallelize 'trunk()..@'
```

### Restoring Files

Discard changes to specific files or restore files from another revision:

```bash
# Discard all uncommitted changes in working copy (restore from parent)
jj restore

# Discard changes to specific files
jj restore path/to/file.txt

# Restore files from a specific revision
jj restore --from <change-id> path/to/file.txt
```

### Inspecting and Tracking Files (`jj file`)

Inspect file state at specific historical revisions without switching branches or checking out working copies:

```bash
# List all tracked files at a specific revision
jj --no-pager --color=never file list -r <change-id>

# Print file contents from a specific historical revision directly to stdout
jj --no-pager --color=never file show -r <change-id> path/to/file.txt

# Stop tracking a file without deleting it from the filesystem.
# The path must already match an ignore rule.
jj file untrack path/to/file.txt

# Delete a file from a revision without checking that revision out.
# Non-interactive. Descendants are rebased onto the updated commit.
jj file delete -r <change-id> path/to/file.txt
```

`jj file edit` always opens `ui.editor`. Do not run it.

`jj file untrack` refuses to untrack a path that is not already ignored. First edit `.gitignore` for a shared rule or `.git/info/exclude` for a local rule, verify that the path matches, and only then run `jj file untrack`. `.jj/ignore` is useful for untracked local files, but it does not satisfy `file untrack`'s precondition.

`jj file delete --restore-descendants` keeps descendant file content instead of rebasing the diff. Pass it only when that is the intended result.

### Ignoring Files (`.gitignore` vs `.jj/ignore`)

Jujutsu respects standard `.gitignore` files in the repository. In addition, you can specify local-only ignore rules:

- **`.gitignore`**: Tracked in git, shared across all repository clones and team members. As of jj 0.46.0 these rules still apply when the ignore file is outside the workspace's sparse patterns, so a sparse working copy does not start tracking ignored files. In-tree `.gitignore` symlinks are skipped.
- **`.jj/ignore`**: Untracked, private to your local clone. Use `.jj/ignore` for agent scratchpads, temporary debug dumps, or local tools that should never be committed to git.

### Inspecting Configuration (`jj config`)

Query Jujutsu configuration non-interactively without opening config editors (user config: `~/.config/jj/config.toml`; repo config: `<repo>/.jj/repo/config.toml`):

```bash
# List all active configuration settings (from user and repo configs)
jj --no-pager --color=never config list

# Query a specific configuration value
jj --no-pager --color=never config get user.name
jj --no-pager --color=never config get user.email

# Safe query when a key may be unset (exits 0 with warning instead of failing; avoids || true)
jj --no-pager --color=never config list revsets.bookmark-advance-to
```

## Working with Bookmarks (Branches)

Bookmarks are jj's equivalent to git branches. Use `jj bookmark set <name> -r <revset>` (defaults to `-r @`): it creates or moves the bookmark idempotently.

For safety, `bookmark set` and `bookmark move` refuse to move a bookmark backward or sideways by default. If that movement is intentional, inspect the graph first, then use `--allow-backwards`. Do not add this flag automatically after an error: moving a shared bookmark backward can require a force-push and overwrite collaborators' published history.

```bash
jj bookmark set my-feature -r @             # Create or move bookmark (idempotent)
jj bookmark create my-feature -r @          # Explicitly create a new bookmark
jj bookmark move my-feature --to <change-id>

# Deliberately move backward/sideways only after inspecting the graph
jj --no-pager --color=never log -r 'my-feature | <change-id>'
jj bookmark set my-feature -r <change-id> --allow-backwards

# Advance closest ancestor bookmarks forward (--to defaults to revsets.bookmark-advance-to, which defaults to @)
jj bookmark advance
jj bookmark advance --to @-

jj --no-pager --color=never bookmark list
jj bookmark rename old-name new-name
jj bookmark delete my-feature               # Marks deletion to push to remote
jj bookmark forget my-feature               # Removes locally without pushing deletion
jj bookmark track my-feature@origin
jj bookmark untrack my-feature@origin

# Resolve a conflicted bookmark (shown as my-feature?? in bookmark list after fetch/rebase)
jj --no-pager --color=never log -r 'bookmarks(exact:"my-feature")'
jj bookmark set my-feature -r <target-commit-id> --allow-backwards
```

## Workspaces

A **workspace** is a working copy plus its associated repo. One repo can have multiple workspaces — each with its own working directory and working-copy commit (`@`, shown as `<workspace-name>@` in `jj log`) — all sharing the same commits, operations, and bookmarks. This is jj's equivalent of `git worktree`, ideal for parallel subagents or isolated test/build checkouts.

### Common commands

```bash
# Create a new workspace under the trusted .jj-workspaces/ directory (defaults: name = basename of path).
# Always pass --colocate so the workspace is a Git worktree and Git-dependent tools keep working.
# --sparse-patterns full avoids inheriting a sparse parent (defaults to copy).
jj workspace add --colocate --sparse-patterns full .jj-workspaces/my-tests
jj workspace add --colocate --sparse-patterns full --name tests -r <change-id> .jj-workspaces/my-tests

# Run jj commands against another workspace without changing directories (stays inside Bash(jj *))
jj --no-pager --color=never -R .jj-workspaces/my-tests status

# Inspect. list/root show every recorded path, including unreachable ones.
jj --no-pager --color=never workspace list
jj --no-pager --color=never workspace root [--name <ws>]

# Unregister a workspace (removes Git worktree registration if colocated; leaves directory on disk)
jj workspace forget [<ws>]

# Snapshot the working copy, then delete the workspace directory from disk.
# Cannot remove the main workspace. Requires explicit authorization.
jj workspace remove <ws>

# Rename current workspace
jj workspace rename <new-name>
```

### Key semantics & agent guidance

- **Isolation by default.** `jj workspace add` gives the new workspace its own fresh empty commit; workspaces don't start out sharing `@`, and on-disk files are never live-mirrored between them.
- **Propagation at command boundaries.** Each jj command snapshots the target workspace's files and reads the op log, so it sees commits/bookmarks made by other workspaces.
- **Stale working copy.** If another workspace rewrites a workspace's `@` (via `squash`, `rebase`, `abandon`), jj refuses commands there until you run `jj workspace update-stale` (or `jj -R <ws-path> workspace update-stale`).
- **Never share `@` across active workspaces.** `jj edit <id>` lets two workspaces point at the same change without warning. When one mutates it, the other goes stale and un-snapshotted edits become a **divergent commit** (`xyz??`).
- **Use `jj -R <path>` instead of `cd <path> && jj ...`.** Shell `cd` does not persist across tool calls and `cd ... && jj ...` breaks `Bash(jj *)`.
- **Clean up with `jj workspace remove <name>`.** It snapshots first and stays inside `Bash(jj *)`. Never `rm -rf` a workspace directory.
- **Cross-workspace undo.** If `jj undo` or `jj redo` refuses because the operation was in another workspace, stop. Do not pass `--allow-cross-workspace`.

### Sparse Workspaces (`jj sparse`)

For large repositories or multi-agent workflows, sparse checkouts limit the files materialized in a workspace to reduce disk I/O and index overhead:

```bash
jj --no-pager --color=never sparse list
jj sparse set --clear --add src/ --add packages/backend/
jj sparse set --add packages/frontend/
jj sparse set --remove legacy/
jj sparse set --reset
```

### Multi-Agent Coordinator Playbook

When coordinating parallel subagents, use `jj workspace` to give each agent an isolated working copy attached to the same repository.

#### 0. Choose the Workspace Location (Trust Boundary)

Agent tools (Claude Code, Cursor, Antigravity, and others) grant file trust to the directory the session was launched in and everything beneath it. A sibling such as `../agent-db` is outside that boundary, triggering permission prompts on every file read/write.

**Put workspaces inside the coordinator's launch directory, under `.jj-workspaces/`.**

- Every tool already trusts that tree, so no per-tool allowlist or settings change is needed.
- jj 0.46.0 does not snapshot a nested workspace into the parent's working copy (`jj status` and `jj file list` stay clean without any ignore rule).
- Git-side tools, editors, and `rg`-style indexers still need `.jj-workspaces/` ignored. Prefer a global ignore (Git's `core.excludesFile`) or add `/.jj-workspaces/` to `.git/info/exclude` once. Both are local and untracked. Do not add it to tracked `.gitignore` unless asked.
- `jj workspace add` does not create intermediate directories. Create `.jj-workspaces/` once before the first `add` (`mkdir -p` is outside `Bash(jj *)`, so ask the user to approve it rather than widening permissions).
- In harnesses with built-in subagent workspace modes (e.g. Antigravity's `Workspace: "inherit"` or Claude Code's git-only `.claude/worktrees/`), keep the harness workspace set to `inherit` and manage isolation through `.jj-workspaces/<agent>`.
- If workspaces must live outside the launch directory, the user must configure tool-specific directory grants (e.g. `--add-dir` in Claude Code); never edit settings files or enable `bypassPermissions`.

#### 1. Setup from Coordinator Workspace

```bash
# Check for any leftover workspaces from an interrupted prior run (remove or forget before re-adding)
jj --no-pager --color=never workspace list

# Bring trunk up to date
jj git fetch
jj rebase --onto main@origin

# Read the commit id and pass that literal to --revision (never use $() or a floating bookmark name)
jj --no-pager --color=never log -r main -T 'commit_id' --no-graph

# Create isolated colocated workspaces under .jj-workspaces/
jj workspace add --colocate --sparse-patterns full --revision <pinned-commit-id> .jj-workspaces/agent-db
jj workspace add --colocate --sparse-patterns full --revision <pinned-commit-id> .jj-workspaces/agent-ui
jj workspace add --colocate --sparse-patterns full --revision <pinned-commit-id> .jj-workspaces/agent-api

# Verify
jj --no-pager --color=never workspace list
```

#### 2. Brief Each Agent with Explicit Contracts

Subagents start in the coordinator's CWD and `cd` does not persist across tool calls. Instruct each parallel agent:
- **File paths**: Read and edit files using full paths under `<coordinator-root>/.jj-workspaces/agent-db/...`.
- **jj commands**: Always pass `-R .jj-workspaces/agent-db` (e.g. `jj --no-pager --color=never -R .jj-workspaces/agent-db status`). Never chain `cd ... && jj ...`, which breaks `Bash(jj *)` and risks running in the coordinator root if `cd` is omitted.
- **Scope & boundaries**: Only touch assigned paths (e.g. `db/`). Never run `jj edit`, `jj squash`, or `jj rebase` on other workspaces' commits, and never touch shared bookmarks (`main`).
- **Finish contract**: Commit and advance to an empty working copy with `jj -R .jj-workspaces/agent-db commit -m "db: add user schema"` (or `jj -R ... desc -m "..."` then `jj -R ... new`). This parks `agent-db@` on a fresh empty commit and leaves the finished work cleanly on `agent-db@-`.

#### 3. Merge Back & Cleanup (from Coordinator Workspace)

Use the revset `<pinned-commit-id>..<ws>@ & ~empty()` to select all non-empty commits in a subagent's stack. This works whether the subagent created one commit or multiple commits, and even if it forgot to run `jj new` at the end:

```bash
# 1. Verify each agent's full stack diff against the pinned base
jj --no-pager --color=never diff --from <pinned-commit-id> --to 'heads(<pinned-commit-id>..agent-db@ & ~empty())' --stat
jj --no-pager --color=never diff --from <pinned-commit-id> --to 'heads(<pinned-commit-id>..agent-ui@ & ~empty())' --stat
jj --no-pager --color=never diff --from <pinned-commit-id> --to 'heads(<pinned-commit-id>..agent-api@ & ~empty())' --stat

# 2. Optional Pre-Integration Check: Create a local megamerge to verify all stacks compose without conflicts
jj new 'heads(<pinned-commit-id>..agent-db@ & ~empty())' 'heads(<pinned-commit-id>..agent-ui@ & ~empty())' 'heads(<pinned-commit-id>..agent-api@ & ~empty())' -m "Local integration test megamerge"
jj --no-pager --color=never log -r @ -T 'conflict' --no-graph
# Run project test suite here if desired, then abandon the temporary megamerge:
jj abandon @

# 3A. Option A (Local Stack): Combine parallel agent stacks into a single linear stack on <pinned-commit-id>
jj rebase -s 'roots(<pinned-commit-id>..agent-db@ & ~empty())' --onto <pinned-commit-id>
jj rebase -s 'roots(<pinned-commit-id>..agent-ui@ & ~empty())' --onto 'heads(<pinned-commit-id>..agent-db@ & ~empty())'
jj rebase -s 'roots(<pinned-commit-id>..agent-api@ & ~empty())' --onto 'heads(<pinned-commit-id>..agent-ui@ & ~empty())'

# 3B. Option B (Separate PR Branches): Keep stacks independent and publish feature bookmarks
jj rebase -s 'roots(<pinned-commit-id>..agent-db@ & ~empty())' --onto <pinned-commit-id>
jj rebase -s 'roots(<pinned-commit-id>..agent-ui@ & ~empty())' --onto <pinned-commit-id>
jj bookmark set agent-db -r 'heads(<pinned-commit-id>..agent-db@ & ~empty())'
jj bookmark set agent-ui -r 'heads(<pinned-commit-id>..agent-ui@ & ~empty())'
jj git push --dry-run -b agent-db
jj git push --dry-run -b agent-ui
jj git push -b agent-db
jj git push -b agent-ui

# 4. After user authorization, snapshot and remove each workspace directory
jj workspace remove agent-db
jj workspace remove agent-ui
jj workspace remove agent-api
```

Do not move or push `main`/`master`, and do not point a feature bookmark at the coordinator's `@-`. Prefer `jj workspace remove` when directory deletion is authorized (`jj workspace forget` only unregisters the workspace and leaves the directory on disk).

## Git Integration

### Cloning, Initializing, and Fetching

```bash
jj git clone <url>                          # Clone a git repository
jj git init --colocate                      # Initialize jj in an existing git repo
jj git fetch                                # Fetch all branches from default remote
jj git fetch --remote <remote-name>         # Fetch from a specific remote
jj git fetch -b <branch-name>               # Fetch specific branch
```

After fetching, rebase your work onto the updated trunk: `jj rebase --onto main`.

### Colocated Safety & Git Pre-Commit Hooks (`jj fix`)

- **Detached HEAD is normal**: A colocated repo contains both `.jj/` and `.git/` with Git `HEAD` intentionally detached at jj's working copy. Never run `git checkout` or `git switch`. If direct Git access is genuinely required, stop and ask the user (it falls outside `Bash(jj *)`).
- **Pre-commit hooks do not run automatically**: Jujutsu snapshots continuously without triggering Git `pre-commit` hooks (Husky, lefthook, lint-staged). Run the project's formatters, linters, and tests explicitly before finishing with `jj new`. If `fix.tools` is configured (`jj --no-pager --color=never config list fix.tools`), run `jj fix -s 'roots(trunk()..@)'` to format all mutable commits in your stack non-interactively.

### Pushing Changes

**Before pushing, ensure:**
1. Your bookmark points to the intended commit (`-r @` or `-r @-` — bookmarks do not auto-advance like git branches).
2. The commits are refined and atomic.
3. The user has explicitly requested the push.

Keep every push explicit. jj 0.46.0 can push several remotes at once (`--remote` is repeatable; `git.push` can name them) and `revsets.git-push` can change which revisions a bare `jj git push` selects. Never run bare `jj git push`, and never move or push `main`/`master` unless the user explicitly asked to publish that bookmark.

```bash
# Safely set (create or move) bookmark to the finished commit (e.g. @- after jj new, or @ before jj new)
jj bookmark set my-feature -r @-

# Preview what will change on the remote without executing the push
jj git push --dry-run -b my-feature

# Push the bookmark to remote (or specify --remote explicitly)
jj git push -b my-feature
jj git push --bookmark my-feature --remote origin

# Push a revision directly by change ID (creates an auto-named remote branch)
jj git push -c <change-id>
```

## Handling Conflicts

jj allows commits to contain unresolved conflicts. Inspect both the working copy and the affected stack:

```bash
jj --no-pager --color=never status
jj --no-pager --color=never log -r 'conflicts()'
```

**Agent conflict resolution**: Do not use `jj resolve` because it launches an interactive merge tool. Edit conflicted files directly, but do not assume Git's simple `<<<<<<<` / `=======` / `>>>>>>>` three-way format. Jujutsu can materialize snapshot sections marked with `+++++++` and one or more diff sections marked with `%%%%%%%` inside the outer `<<<<<<< Conflict ...` and `>>>>>>> Conflict ... ends` markers. A conflict can have more than two sides, so understand every section before choosing the final content and removing the complete marker block.

After editing, re-run both `jj --no-pager --color=never status` and `jj --no-pager --color=never log -r 'conflicts()'`. `jj st` only describes `@`; a rebase can leave a conflict in another revision. Do not report resolution complete while any relevant revision still appears in `conflicts()`.

## Handling Divergent Commits

Divergence happens when the same Change ID has multiple conflicting commit versions (marked `<change-id> ??` in `jj log`), typically when a change is modified concurrently across workspaces or operations.

```bash
# 1. Find all divergent commits across the repository
jj --no-pager --color=never log -r 'divergent()'

# 2. Try non-interactive converge first (aborts instead of prompting when ambiguous; never run bare jj converge)
jj converge --no-interactive

# 3A. If converge aborts: keep one version and discard the other using its Commit ID (not Change ID)
jj abandon <obsolete-commit-id>

# 3B. Or combine both versions using specific Commit IDs
jj squash --from <source-commit-id> --into <target-commit-id> -u
```

## Megamerges (Multi-Branch Integration & Testing)

A **megamerge** is a local octopus merge commit whose parents are multiple in-flight WIP branches, allowing you to build and test multiple independent features simultaneously:

```bash
# 1. Create an octopus merge commit across multiple branches and advance @ on top of it
jj new feature-a feature-b feature-c -m "Local megamerge (test only)"
jj new

# 2. Run test suites; distribute fixes from @ back into the parent branch that last touched those lines
jj absorb

# 3. When trunk updates, restack all mutable branches and collapse redundant edges
jj rebase --onto trunk() --source 'roots(trunk()..) & mutable()' --simplify-parents

# 4. Never push the megamerge itself; push each component bookmark individually
jj git push -b feature-a
jj git push -b feature-b
```

## Preserving Commit Quality

Before considering work done:
1. **Review your commit**: `jj --no-pager --color=never show --git @` or `jj --no-pager --color=never diff --git`
2. **Keep it atomic & well-described**: One logical change per commit; imperative sentence-case title with no trailing period (e.g. `"Add login endpoint"`, `"Fix null pointer in payment processor"`).
3. **Split or move unrelated edits**: Use `jj restore`, `jj squash -u`, or `jj absorb`.
4. **Protect the completed commit**: Always finish with `jj new` (or `jj commit -m "..."`) so `@` sits on a fresh empty revision.

## Quick Reference

| Action | Command |
|--------|---------|
| Describe / commit | `jj desc -m "msg"` (stays on `@`) or `jj commit -m "msg"` (advances `@` to empty child) |
| View status / log | `jj --no-pager --color=never status` / `jj --no-pager --color=never log` |
| View diff / commit | `jj --no-pager --color=never diff --git [paths]` / `jj --no-pager --color=never show --git <id>` |
| Compare patch revisions | `jj --no-pager --color=never interdiff --from <old> --to <new> --git` |
| Edit / squash / absorb | `jj edit <id>` / `jj squash -u` / `jj absorb [paths]` (verify with `jj --no-pager --color=never op show -p`) |
| Rebase / parallelize / dup | `jj rebase --onto <dest>` / `jj parallelize <revs>` / `jj duplicate <id>` |
| Abandon / clean empty | `jj abandon <id>` / `jj abandon 'empty() & mutable() & ~root() & ~@'` |
| Undo / redo / op log | `jj undo` / `jj redo` / `jj --no-pager --color=never op log -n 10` |
| Preview / restore op | `jj --no-pager --color=never status --at-op=<id>` / `jj op restore <operation-id>` |
| Change evolution | `jj --no-pager --color=never evolog -p -r <change-id>` |
| File inspect / restore | `jj --no-pager --color=never file list -r <id>` / `jj --no-pager --color=never file show -r <id> <path>` / `jj restore [paths]` |
| File untrack / delete | `jj file untrack <path>` (must be ignored first) / `jj file delete -r <id> <path>` (never `jj file edit`) |
| Inspect config | `jj --no-pager --color=never config list [<key>]` / `jj --no-pager --color=never config get <key>` |
| Bookmarks | `jj bookmark set <name> -r <target>` / `jj bookmark advance [--to <target>]` / `jj bookmark track <name>@<remote>` |
| Fetch / push | `jj git fetch` / `jj git push --dry-run -b <name>` / `jj git push -b <name>` / `jj git push -c <id>` |
| Workspaces | `jj workspace add --colocate --sparse-patterns full .jj-workspaces/<name>` / `jj -R .jj-workspaces/<name> <cmd>` |
| Workspace cleanup | `jj --no-pager --color=never workspace list` / `jj workspace remove <name>` / `jj workspace update-stale` |
| Sparse patterns | `jj --no-pager --color=never sparse list` / `jj sparse set --clear --add <paths>` / `jj sparse set --reset` |
