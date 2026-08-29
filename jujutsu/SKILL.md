---
name: jujutsu
description: "**REQUIRED** - Always activate FIRST on any git/VCS operations (commit, status, branch, push, etc.), especially when HEAD is detached. If `.jj/` exists -> this is a Jujutsu (jj) repo - raw git commands can corrupt data. Essential git safety instructions inside. DO NOT IGNORE."
allowed-tools: Bash(jj *)
---

# Jujutsu (jj) Version Control System

This skill helps you work with Jujutsu, a Git-compatible VCS with mutable commits and automatic rebasing.

**Tested with jj v0.44.0** - Commands may differ in other versions.

## Important: Automated/Agent Environment

When running as an agent:

1. **Always use `--no-pager`** to prevent commands from opening an interactive pager (like `less`), which will hang the agent:

```bash
# Always use --no-pager on commands that produce output
jj --no-pager log          # NOT: jj log
jj --no-pager diff         # NOT: jj diff
jj --no-pager show <id>    # NOT: jj show <id>
```

2. **Always use `-m` flags** to provide messages inline rather than relying on editor prompts:

```bash
# Always use -m to avoid editor prompts
jj desc -m "message"      # NOT: jj desc
jj squash -m "message"    # NOT: jj squash (which opens editor)
```

Editor-based commands will fail in non-interactive environments.

3. **Verify operations with `jj st`** after mutations (`squash`, `abandon`, `rebase`, `restore`) to confirm the operation succeeded.

4. **Always finish by creating a new empty commit (`jj new`)**: Never leave the working copy (`@`) pointing to a completed commit. When you are done with your task or changes, always run `jj new` to move to a fresh, empty commit so subsequent agent actions or CLI commands do not accidentally modify the completed revision.

## Core Concepts

### The Working Copy is a Commit

In jj, your working directory is always a commit (referenced as `@`). Changes are automatically snapshotted when you run any jj command. There is no staging area.

There is no need to run `jj commit`.

### Commits Are Mutable

**CRITICAL**: Unlike git, jj commits can be freely modified after creation. You can update descriptions, squash changes, rebase, and absorb — all without creating new commits. See "Essential Workflow" below for the recommended working pattern.

### Change IDs vs Commit IDs

- **Change ID**: A stable identifier (like `tqpwlqmp`) that persists when a commit is rewritten — prefer these when referencing commits
- **Commit ID**: A content hash (like `3ccf7581`) that changes when commit content changes

### Revsets

jj uses a revset language to select commits in commands. Common revsets:

- `@` — the working copy commit
- `@-` — the parent of the working copy
- `::@` — all ancestors of `@`
- `@::` — all descendants of `@`
- `trunk()..@` — commits between trunk and `@` (your branch)
- `bookmarks()` — all commits with bookmarks
- `conflicts()` — commits containing unresolved merge conflicts
- `divergent()` — commits with divergent change IDs (`??`)
- `empty() & ~root()` — empty commits (useful for cleanup)
- `immutable()` — commits protected from rewriting (e.g., trunk/pushed heads)

Use revsets with `-r` flags: `jj log -r 'trunk()..@'` or `jj log -r 'conflicts()'`.

## Essential Workflow

### Starting Work: Describe First, Then Code

**Always create your commit message before writing code:**

1. **Branching off trunk/main or a specific base**: When starting independent work, create your new revision directly off your intended base (e.g. `main` or a specific commit) rather than accidentally stacking on your current working revision:

```bash
# Start independent work directly off main/trunk with message
jj new main -m "Add user authentication to login endpoint"

# Or off any specific revision
jj new <change-id> -m "Add validation to user input forms"
```

2. **Continuing on current branch**: If working on top of the current revision, validate that `@` is empty with `jj st`. If it is not empty, run `jj new` first:

```bash
# Ensure you are on a blank commit
jj new

# Describe what you intend to do
jj desc -m "Add user authentication to login endpoint"

# Then make your changes - they automatically become part of this commit
# ... edit files ...

# Check status
jj st
```

### Creating Atomic Commits

Each commit should represent ONE logical change. Use this format for commit messages:

```
Examples:
- "Add validation to user input forms"
- "Fix null pointer in payment processor"
- "Remove deprecated API endpoints"
- "Update dependencies to latest versions"
```

### Viewing History

```bash
# View recent commits
jj --no-pager log

# View with patches
jj --no-pager log -p

# View specific commit
jj --no-pager show <change-id>

# View diff of working copy (use --git for familiar +/- format)
jj --no-pager diff --git
```

**IMPORTANT: `jj diff` output format**: The default `jj diff` output uses a side-by-side line number format (e.g. `26   26:`) that looks very different from git's `+`/`-` prefix format. This is **normal and correct** — it is NOT corrupted or showing stale content. However, to avoid confusion, **always use `jj diff --git`** to get standard unified diff format with `+`/`-` lines.

### Moving Between Commits

```bash
# Create a new empty commit on top of current
jj new

# Create new commit with message on top of current
jj new -m "Commit message"

# Create new commit branching off a specific base
jj new main -m "New branch off main"
jj new <base-change-id> -m "New branch off base"

# Edit an existing commit (working copy becomes that commit)
jj edit <change-id>

# Edit the previous commit
jj prev -e

# Edit the next commit
jj next -e
```

### Finishing Work: Always Advance to a New Empty Commit (`jj new`)

**CRITICAL**: When you finish your task, refine a commit, or complete a change:

```bash
# Always run jj new when finished to protect the completed commit
jj new
```

Because jj automatically records changes into the current working-copy commit (`@`), leaving `@` on your completed commit means any subsequent command, agent action, or manual file edit will silently mutate it. Running `jj new` moves `@` to a fresh, empty child commit, safely preserving your completed work.

## Refining Commits

### Squashing Changes

Move changes from one revision into another without having to manually rebase:

```bash
# Squash all changes from current commit into its parent
jj squash

# Squash changes into a specific ancestor commit
jj squash --into <change-id>

# Squash only specific files into an ancestor commit
jj squash --into <change-id> path/to/file.txt

# Pull changes from another revision into the current commit
jj squash --from <change-id>

# Keep destination description without editor prompt (or supply new message with -m)
jj squash --into <change-id> -u
jj squash --into <change-id> -m "Updated commit message"
```

**Note**: `jj squash -i` opens an interactive UI and will hang in agent environments. Avoid it.

### Splitting Commits

**Warning**: `jj split` is interactive and will hang in agent environments. To divide a commit, use `jj restore` to move changes out, then create separate commits manually.

### Absorbing Changes

Automatically distribute changes to the commits that last modified those lines:

```bash
# Absorb working copy changes into appropriate ancestor commits
jj absorb
```

### Abandoning Commits

Remove a commit entirely (descendants are rebased to its parent):

```bash
jj abandon <change-id>
```

### Undoing Operations and Multi-Step Recovery

Jujutsu records every repo mutation in an append-only operation log.

```bash
# Reverse the single most recent operation
jj undo

# Redo the most recently undone operation
jj redo

# View recent operations (always pass --no-pager and optionally -n to limit output)
jj --no-pager op log -n 10

# Restore the entire repository state to a specific prior operation ID
jj op restore <operation-id>
```

This makes recovering from complex multi-step mistakes (like a sequence of bad rebases, squashes, or accidental abandons) safe and trivial.

### Rebasing Commits

Move commits to a different parent:

```bash
# Rebase current branch onto a destination
jj rebase -d <destination>

# Rebase a specific revision (without descendants) onto a destination
jj rebase -r <change-id> -d <destination>

# Rebase a revision and all its descendants
jj rebase -s <change-id> -d <destination>

# Rebase onto trunk (common: update your branch to latest main)
jj rebase -d main
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

## Working with Bookmarks (Branches)

Bookmarks are jj's equivalent to git branches.

**Agent Tip (Idempotent Bookmark Setting)**: Use `jj bookmark set <name> -r <revset>` (defaults to `-r @`). If the bookmark exists, it moves it; if not, it creates it. This avoids errors from calling `create` on existing bookmarks or `move` on new ones.

```bash
# Create or move bookmark to current commit (idempotent - recommended for agents)
jj bookmark set my-feature -r @

# Explicitly create a new bookmark
jj bookmark create my-feature -r @

# Move an existing bookmark to a different commit
jj bookmark move my-feature --to <change-id>

# List bookmarks
jj --no-pager bookmark list

# Delete a bookmark (marks deletion to push to remote)
jj bookmark delete my-feature

# Forget a bookmark (removes locally without pushing deletion)
jj bookmark forget my-feature
```

## Workspaces

A **workspace** is a working copy plus its associated repo. One repo can have multiple workspaces — each with its own working directory and working-copy commit (`@`) — all sharing the same commits, operations, and bookmarks. This is jj's equivalent of `git worktree`.

Useful for running a long build or test in one workspace while editing in another. Workspaces are a rarely-needed feature; consult the [official docs](https://docs.jj-vcs.dev/latest/working-copy/#workspaces) for anything beyond the basics below.

### Common commands

```bash
# Create a new workspace (defaults: name = basename of path, parent = current @'s parent)
jj workspace add ../my-tests
jj workspace add --name tests -r <change-id> ../my-tests   # explicit name and base

# Inspect
jj --no-pager workspace list
jj workspace root [--name <ws>]

# Remove (does NOT delete files on disk — rm the directory separately)
jj workspace forget [<ws>]

# Rename current workspace
jj workspace rename <new-name>
```

In `jj log`, each workspace's `@` appears as `<workspace-name>@`.

### Key semantics

- **Isolation by default.** `jj workspace add` gives the new workspace its own fresh empty commit; workspaces don't start out sharing `@`, and on-disk files are never live-mirrored between them.
- **Propagation at command boundaries.** Each jj command snapshots the current workspace's files and reads the op log, so it sees commits/bookmarks made by other workspaces. There is no filesystem watcher.
- **Stale working copy.** If another workspace rewrites this workspace's `@` (e.g. via `jj squash`, `rebase`, `abandon`), jj refuses commands here until you run `jj workspace update-stale`. Same recovery path if a command was interrupted mid-update.
- **Shared `@` is sharp-edged.** `jj edit <id>` lets two workspaces point at the same change without warning. When one mutates it, the other goes stale; if the stale one had un-snapshotted edits, `update-stale` preserves them as a **divergent commit** (same change ID, shown as `xyz??` in `jj log`) that you must resolve. Avoid sharing `@` unless both workspaces are read-only.

### Agent guidance

- Always pass `--no-pager` to `jj workspace list`.
- Don't `jj edit` a change another workspace already has as its `@` — main cause of accidental divergence.
- Don't `rm -rf` a workspace directory without also running `jj workspace forget <name>`.

## Git Integration

### Working with Existing Git Repos

```bash
# Clone a git repository
jj git clone <url>

# Initialize jj in an existing git repo
jj git init --colocate
```

### Fetching Remote Changes

```bash
# Fetch all branches from the default remote
jj git fetch

# Fetch from a specific remote
jj git fetch --remote <remote-name>

# Fetch specific branches
jj git fetch -b <branch-name>
```

After fetching, rebase your work onto the updated trunk: `jj rebase -d main`

### Switching Between jj and git (Colocated Repos Only)

**This section only applies to colocated repos** (where both `.jj/` and `.git/` exist). In non-colocated repos, do not use git commands — they will corrupt jj state.

In a colocated repository, you can use both jj and git commands with care:

**Switching to git mode** (e.g., for merge workflows):
```bash
# First, ensure your jj working copy is clean
jj st

# Then checkout a branch with git
git checkout <branch-name>
```

**Switching back to jj mode**:
```bash
# Use jj edit to resume working with jj
jj edit <change-id>
```

**Important notes:**
- Git may complain about uncommitted changes if jj's working copy differs from the git HEAD
- ALWAYS ensure your work is committed in jj before switching to git
- After git operations, jj will detect and incorporate the changes on next command

### Pushing Changes

When the user asks you to push changes:

```bash
# Push a specific bookmark to the remote
jj git push -b <bookmark-name>

# Example: push the main bookmark
jj git push -b main
```

**Before pushing, ensure:**
1. Your bookmark points to the correct commit (bookmarks don't auto-advance like git branches)
2. The commits are refined and atomic
3. The user has explicitly requested the push

**IMPORTANT**: Unlike git branches, jj bookmarks do not automatically move when you create new commits. Use `jj bookmark set` to safely create or move the bookmark before pushing:

```bash
# Safely set (create or move) bookmark to the current commit
jj bookmark set my-feature -r @

# Then push it
jj git push -b my-feature
```

## Handling Conflicts

jj allows committing conflicts — you can resolve them later:

```bash
# View conflicts
jj st
```

**Agent conflict resolution**: Do not use `jj resolve` (interactive). Instead, edit the conflicted files directly to remove conflict markers, then run `jj st` to verify resolution.

## Handling Divergent Commits

Divergence happens when the same Change ID has multiple conflicting commit versions (often marked as `<change-id> ??` in `jj log`). This usually occurs when a change is modified concurrently in two workspaces or operations.

### Diagnosing Divergence

```bash
# Find all divergent commits across the repository
jj --no-pager log -r 'divergent()'
```

### Resolving Divergence

To resolve divergent commits, choose one of these strategies depending on intent:

1. **Keep one version and discard the other**: Use the specific **Commit ID** (not Change ID) to abandon the obsolete version:
```bash
jj abandon <obsolete-commit-id>
```

2. **Combine both versions**: Squash changes from one version into the other using specific Commit IDs:
```bash
jj squash --from <source-commit-id> --into <target-commit-id>
```

## Preserving Commit Quality

**IMPORTANT**: Because commits are mutable, always refine them before considering work done:

1. **Review your commit**: `jj --no-pager show @` or `jj --no-pager diff --git`
2. **Is it atomic?** One logical change per commit
3. **Is the message clear?** Use imperative verb phrase in sentence case format with no full stop: e.g. "Add login endpoint", "Fix null pointer in payment processor", "Remove deprecated API endpoints"
4. **Are there unrelated changes?** Use `jj restore` to move changes out, then create separate commits
5. **Should changes be elsewhere?** Use `jj squash` or `jj absorb`
6. **Protect the completed commit**: Always run `jj new` when done so `@` is on a fresh empty revision rather than sitting directly on your finished commit

## Quick Reference

| Action | Command |
|--------|---------|
| Describe commit | `jj desc -m "message"` |
| View status | `jj st` |
| View log | `jj --no-pager log` |
| View diff | `jj --no-pager diff --git` |
| New commit | `jj new -m "message"` (use `jj st` first; skip if `@` is empty) |
| Edit commit | `jj edit <id>` |
| Squash to parent | `jj squash` |
| Auto-distribute | `jj absorb` |
| Rebase | `jj rebase -d <destination>` |
| Abandon commit | `jj abandon <id>` |
| Undo last operation | `jj undo` |
| Redo operation | `jj redo` |
| View operation log | `jj --no-pager op log -n 10` |
| Restore to operation | `jj op restore <operation-id>` |
| Restore files | `jj restore [paths]` |
| Set / create bookmark | `jj bookmark set <name> -r <target>` |
| Fetch remote | `jj git fetch` |
| Push bookmark | `jj git push -b <name>` |
| Add workspace | `jj workspace add <path>` |
| List workspaces | `jj --no-pager workspace list` |
| Forget workspace | `jj workspace forget [name]` |
| Fix stale working copy | `jj workspace update-stale` |

## Best Practices Summary

1. **Describe first**: Set the commit message before coding
2. **One change per commit**: Keep commits atomic and focused
3. **Use change IDs**: They're stable across rewrites
4. **Refine commits**: Leverage mutability for clean history
5. **Embrace the workflow**: No staging area, no stashing - just commits
6. **Always finish with `jj new`**: Protect completed work by advancing `@` to a new empty revision
