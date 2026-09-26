---
name: jujutsu
description: "**REQUIRED** - Always activate FIRST on any git/VCS operations (commit, status, branch, push, etc.), especially when HEAD is detached. If `.jj/` exists -> this is a Jujutsu (jj) repo - raw git commands can corrupt data. Essential git safety instructions inside. DO NOT IGNORE."
allowed-tools: Bash(jj *)
---

# Jujutsu (jj) Version Control System

This skill helps you work with Jujutsu, a Git-compatible VCS with mutable commits and automatic rebasing.

**Tested with jj v0.45.1** (compatible with `jj v0.44.0` - `v0.45.1`) - Commands may differ in other versions.

## Important: Automated/Agent Environment

When running as an agent:

1. **Always use `--no-pager` and explicit subcommands**: Never invoke bare `jj` (which triggers user-configured `ui.default-command`). Always pass explicit subcommands and `--no-pager` to prevent commands from opening an interactive pager (like `less`), which will hang the agent:

```bash
# Always use --no-pager on commands that query status or produce output
jj --no-pager status             # NOT: bare jj status or jj st (can open pager)
jj --no-pager log                # NOT: jj log or bare jj
jj --no-pager diff --git         # NOT: jj diff (always include --git)
jj --no-pager interdiff --from <old-revision> --to <new-revision> --git
jj --no-pager show --git <id>    # NOT: jj show <id> (always include --git)
jj --no-pager <cmd> --help       # NOT: jj <cmd> --help (can open pager)
```

2. **Always use `-m` flags** to provide messages inline rather than relying on editor prompts:

```bash
# Always use -m to avoid editor prompts
jj desc -m "message"      # NOT: jj desc
jj squash -m "message"    # NOT: jj squash (which opens editor)
```

Editor-based commands will fail in non-interactive environments.

3. **Never use `-i` or `--interactive` flags**: Subcommands like `squash -i`, `split`, `diff -i`, `diffedit`, `restore -i`, `absorb -i` launch interactive terminal prompts or diff editors that will hang automated agents. Always use non-interactive flags or explicit path arguments.

4. **Verify operations after mutations** (`squash`, `abandon`, `rebase`, `restore`). Run `jj --no-pager status`, inspect the affected graph with `jj --no-pager log`, and check relevant content invariants; a successful exit alone does not prove that the intended changes were preserved.

5. **Never run `git checkout`/`git switch` to "fix" detached HEAD**: In colocated repos (`.jj/` + `.git/`), Git HEAD is intentionally detached to point at jj's `@` or `@-`. Linters or tools reporting "detached HEAD" are encountering normal jj operation. Do not attempt to checkout git branches.

6. **Always finish by creating a new empty commit (`jj new`)**: Never leave the working copy (`@`) pointing to a completed commit. When you are done with your task or changes, always run `jj new` to move to a fresh, empty commit so subsequent agent actions or CLI commands do not accidentally modify the completed revision.

7. **NEVER use or suggest `--ignore-immutable`**: Immutable commits (such as `main`, `trunk()`, or remote branches) are strictly protected. If an operation fails with a `Commit <id> is immutable` error, **do NOT attempt to bypass it with `--ignore-immutable`**. Instead, create a new change on top of the immutable commit using `jj new <base>` or rebase your mutable commits onto it.

8. **Stay within the declared command boundary**: This skill grants `Bash(jj *)`, not unrestricted shell or Git access. Examples such as `NAME=$(jj ...)` are scripting conveniences whose command line begins with a shell assignment and may therefore require separate permission. Prefer direct revsets in `jj` commands when possible, and never widen permissions merely to avoid a prompt.

## Core Concepts

### The Working Copy is a Commit (`@` vs `@-`)

In jj, your working directory is always a commit (referenced as `@`). Changes are automatically snapshotted when you run any jj command. There is no staging area.

- **`jj desc -m "..."`**: Labels the current working-copy commit `@`.
- **`jj new`**: Creates a fresh, empty commit on top of `@` (the previous commit becomes `@-`).
- **`jj commit -m "..."`**: A convenient one-step shortcut for `jj desc -m "..." && jj new`.

#### The `@` vs `@-` Rule (Where Your Finished Commit Lives)

| Workflow Pattern | Where Your Labeled Commit Is | Bookmark / Push Target |
| :--- | :--- | :--- |
| `jj desc -m "..."` (before `jj new`) | `@` | `-r @` |
| `jj commit -m "..."` | `@-` (new empty `@` is created) | `-r @-` |
| `jj desc -m "..."` then `jj new` | `@-` (new empty `@` is created) | `-r @-` |

### Commits Are Mutable (Except Immutable Heads)

**CRITICAL**: Unlike git, jj commits can be freely modified after creation. You can update descriptions, squash changes, rebase, and absorb — all without creating new commits.

However, certain revisions (such as `trunk()`, `main`, or pushed remote commits) are marked as **immutable** (`immutable()` revset) to prevent altering shared history. Agents must never attempt to rewrite immutable commits or pass `--ignore-immutable`; instead, always branch off with `jj new <base>`.

### Change IDs vs Commit IDs

- **Change ID**: A stable identifier (like `tqpwlqmp`) that persists when a commit is rewritten — prefer these when referencing commits
- **Commit ID**: A content hash (like `3ccf7581`) that changes when commit content changes

### Revsets

jj uses a rich functional revset language to query and select commits:

| Intent | Revset Expression | Description |
|--------|-------------------|-------------|
| **Current Stack** | `trunk()..@` | All commits on current branch since trunk |
| **Stack Tip** | `heads(trunk()..@)` | Top-most commit of the current branch |
| **Stack Root** | `roots(trunk()..@)` | Base commit of the current branch |
| **Recent History** | `ancestors(@, 5)` | Last 5 commits leading up to `@` |
| **Unpushed Commits** | `remote_bookmarks()..` | Commits not yet pushed to any remote |
| **Conflicts** | `conflicts()` | Commits containing unresolved merge conflicts |
| **Divergent** | `divergent()` | Commits with split Change IDs (`??`) |
| **Empty Commits** | `empty() & ~root()` | Empty commits (useful for cleanup) |
| **Mutable Commits** | `mutable()` | All commits that can be freely rewritten |
| **Immutable** | `immutable()` | Commits protected from rewriting |
| **Bookmarks** | `bookmarks()` | Commits marked with bookmarks |

Use revsets with `-r` flags: `jj --no-pager log -r 'trunk()..@'` or `jj --no-pager log -r 'conflicts()'`.

### Machine-Readable Template Queries (`-T` / `--template`)

Agents and scripts can extract specific commit metadata programmatically without terminal graph characters or regex parsing by combining `-T` with `--no-graph`:

```bash
# Query stable Change ID or Commit Hash of @
CHANGE_ID=$(jj --no-pager log -r @ -T 'change_id' --no-graph)
COMMIT_ID=$(jj --no-pager log -r @ -T 'commit_id' --no-graph)

# Check if working copy has changes (outputs "true" or "false")
IS_EMPTY=$(jj --no-pager log -r @ -T 'empty' --no-graph)

# Check if commit has unresolved conflicts (outputs "true" or "false")
HAS_CONFLICTS=$(jj --no-pager log -r @ -T 'conflict' --no-graph)

# Check if commit is protected / immutable (outputs "true" or "false")
IS_IMMUTABLE=$(jj --no-pager log -r @ -T 'immutable' --no-graph)

# Query commit description title (first line)
TITLE=$(jj --no-pager log -r @ -T 'description.first_line()' --no-graph)
```

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
jj --no-pager status
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

### Multi-line Descriptions (Chaining `-m` Flags)

To write multi-paragraph commit messages without opening an editor or risking shell escaping issues, pass multiple `-m` flags. `jj` automatically separates each `-m` with a blank line (title and body paragraphs):

```bash
# First -m is the title, subsequent -m flags are body paragraphs
jj desc \
  -m "Add OAuth2 authentication provider" \
  -m "Introduce Google and GitHub OAuth handlers with token refresh." \
  -m "- Implement callback router\n- Add token refresh middleware"
```

### Viewing History

Use `diff` to compare repository trees. Use `interdiff` to compare how the patch itself changed between two revisions, such as before and after revising or rebasing a change. Always provide both endpoints so the comparison is explicit:

```bash
jj --no-pager interdiff --from <old-revision> --to <new-revision> --git
```

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

**IMPORTANT: Why `jj diff --git` is required**:
1. Default `jj diff` uses a side-by-side line number format (e.g. `26   26:`) rather than standard unified diff format.
2. User configurations often set `ui.diff-formatter` to external diff tools (e.g. Difftastic or Delta). Adding `--git` bypasses external tools and guarantees a clean, machine-parseable unified diff with standard `+`/`-` line prefixes.

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

### Splitting Commits (Non-Interactive Recipe)

`jj split` opens an interactive selection UI and will hang in agent environments. To split an existing commit `<target>` into separate atomic commits non-interactively:

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
jj --no-pager diff --from <target> --to @ --git

# 7. Run the project's relevant tests against the reconstructed stack
# <project-specific test command>

# 8. Only after the tree diff is empty and tests pass, abandon the original
jj abandon <target>

# 9. Verify the rewritten stack from the split tip through its descendants
jj --no-pager log -r '@::'
jj --no-pager status
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
jj --no-pager op show -p
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
# Reverse the single most recent operation
jj undo

# Redo the most recently undone operation
jj redo

# View recent operations (always pass --no-pager and optionally -n to limit output)
jj --no-pager op log -n 10

# Restore the entire repository state to a specific prior operation ID
jj op restore <operation-id>
```

Use operation-level recovery carefully: `jj op restore` restores the state of the entire repository and can undo unrelated work recorded after that operation.

For a targeted view of how one change evolved across rewrites, inspect its evolution log:

```bash
jj --no-pager evolog -p -r <change-id>
```

Use the displayed commit IDs to inspect an earlier version with `jj --no-pager show <commit-id>` or build a new change from one with `jj new <commit-id>`. Prefer this targeted approach when unrelated repository work must remain intact.

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
jj --no-pager file list -r <change-id>

# Print file contents from a specific historical revision directly to stdout
jj --no-pager file show -r <change-id> path/to/file.txt

# Stop tracking a file without deleting it from the filesystem.
# The path must already match an ignore rule.
jj file untrack path/to/file.txt
```

`jj file untrack` refuses to untrack a path that is not already ignored. First edit `.gitignore` for a shared rule or `.git/info/exclude` for a local rule, verify that the path matches, and only then run `jj file untrack`. `.jj/ignore` is useful for untracked local files, but it does not satisfy `file untrack`'s precondition.

### Ignoring Files (`.gitignore` vs `.jj/ignore`)

Jujutsu respects standard `.gitignore` files in the repository. In addition, you can specify local-only ignore rules:

- **`.gitignore`**: Tracked in git, shared across all repository clones and team members.
- **`.jj/ignore`**: Untracked, private to your local clone. Use `.jj/ignore` for agent scratchpads, temporary debug dumps, or local tools that should never be committed to git.

## Working with Bookmarks (Branches)

Bookmarks are jj's equivalent to git branches.

**Agent Tip (Idempotent Bookmark Setting)**: Use `jj bookmark set <name> -r <revset>` (defaults to `-r @`). If the bookmark exists, it moves it; if not, it creates it. This avoids errors from calling `create` on existing bookmarks or `move` on new ones.

For safety, `bookmark set` and `bookmark move` refuse to move a bookmark backward or sideways by default. If that movement is intentional, inspect the graph first, then use `--allow-backwards`. Do not add this flag automatically after an error: moving a shared bookmark backward can require a force-push and overwrite collaborators' published history.

```bash
# Create or move bookmark to current commit (idempotent - recommended for agents)
jj bookmark set my-feature -r @

# Explicitly create a new bookmark
jj bookmark create my-feature -r @

# Move an existing bookmark forward to a different commit
jj bookmark move my-feature --to <change-id>

# Deliberately move backward/sideways only after inspecting the graph
jj --no-pager log -r 'my-feature | <change-id>'
jj bookmark set my-feature -r <change-id> --allow-backwards

# Advance the closest bookmark forward along the stack (to @ or specific target)
jj bookmark advance
jj bookmark advance -r @-

# List bookmarks
jj --no-pager bookmark list

# Rename a bookmark
jj bookmark rename old-name new-name

# Delete a bookmark (marks deletion to push to remote)
jj bookmark delete my-feature

# Forget a bookmark (removes locally without pushing deletion)
jj bookmark forget my-feature

# Track a remote bookmark locally (e.g. from git remote)
jj bookmark track my-feature@origin

# Untrack a remote bookmark (stops synchronizing with remote)
jj bookmark untrack my-feature@origin
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

### Sparse Workspaces (`jj sparse`)

For large repositories or multi-agent workflows, sparse checkouts limit the files materialized in a workspace to reduce disk I/O and index overhead:

```bash
# List active sparse checkout patterns
jj --no-pager sparse list

# Restrict workspace to specific directories
jj sparse set --clear --add src/ --add packages/backend/

# Add or remove directory patterns
jj sparse set --add packages/frontend/
jj sparse set --remove legacy/

# Reset sparse configuration to checkout the entire repo
jj sparse set --reset
```

### Multi-Agent Coordinator Playbook

When coordinating a team of parallel subagents, use `jj workspace` to give each agent an isolated working copy attached to the same repository.

#### 1. Setup from Coordinator Workspace

```bash
# Bring main up to date
jj git fetch
jj rebase --onto main@origin

# CRITICAL: PIN the exact base commit hash (never use floating 'main')
BASE=$(jj --no-pager log -r main -T 'commit_id' --no-graph)

# Create isolated workspaces for each agent rooted at $BASE
jj workspace add ../agent-db --revision "$BASE"
jj workspace add ../agent-ui --revision "$BASE"
jj workspace add ../agent-api --revision "$BASE"

# Verify
jj --no-pager workspace list
```

#### 2. Brief Each Agent with Explicit Contracts

Instruct each parallel agent:
- Workspace path: e.g. `cd /path/to/agent-db`
- Scope: e.g. "Only touch files in `db/`"
- Boundary rules: Never run `jj edit`, `jj squash`, or `jj rebase` on other workspaces. Never touch shared bookmarks (`main`).
- Finish contract: Label changes with `jj desc -m "db: add user schema"` and stop.

#### 3. Merge Back & Cleanup (from Coordinator Workspace)

```bash
# 1. Verify independent diffs
jj --no-pager diff --stat -r <agent-db-commit>
jj --no-pager diff --stat -r <agent-ui-commit>

# 2. Rebase cleanly onto main
jj rebase -s <agent-db-commit> --onto main
jj rebase -s <agent-ui-commit> --onto main

# 3. Update bookmark and push
jj bookmark set main -r @-
jj git push --dry-run -b main
jj git push -b main

# 4. Remove workspace pointers one at a time
jj workspace forget agent-db
jj workspace forget agent-ui
jj workspace forget agent-api
```

`jj workspace forget` does not delete the directories from disk. Directory deletion is a separate filesystem action outside this skill's `Bash(jj *)` permission boundary. Before requesting or performing it, resolve and inspect each path individually, confirm it is the expected forgotten workspace, and obtain authorization for the destructive action. Never use an unverified variable, glob, or multi-path recursive deletion command.

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

After fetching, rebase your work onto the updated trunk: `jj rebase --onto main`

### Colocated Repository Safety

A colocated repository contains both `.jj/` and `.git/`, but agents should still perform version-control operations through `jj` only. Jujutsu keeps Git `HEAD` detached at a commit representing the jj working-copy state, so detached-HEAD warnings from Git-oriented tools are normal and do not need repair.

**Do not run `git checkout` or `git switch` to fix detached HEAD.** Those commands move Git's working tree outside jj's workflow and can create confusing imports or overwrite working-copy state. If a task genuinely requires direct Git operation, stop and request explicit user authorization; it is outside this skill's `Bash(jj *)` permission boundary.

### Git Pre-Commit Hooks Notice

Jujutsu records changes continuously and automatically; it does NOT execute Git `pre-commit` hooks (such as Husky, lefthook, or lint-staged). In projects that rely on Git hooks for formatting or linting, agents must explicitly run the project's formatting and test commands before advancing with `jj new`.

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

# Verify what will change on the remote without executing the push
jj git push --dry-run -b my-feature

# Push the bookmark to remote
jj git push -b my-feature

# Push bookmark explicitly to a specified remote
jj git push --bookmark my-feature --remote origin

# Push a revision directly by change ID
jj git push -c <change-id>
```

## Handling Conflicts

jj allows commits to contain unresolved conflicts. Inspect both the working copy and the affected stack:

```bash
jj --no-pager status
jj --no-pager log -r 'conflicts()'
```

**Agent conflict resolution**: Do not use `jj resolve` because it launches an interactive merge tool. Edit conflicted files directly, but do not assume Git's simple `<<<<<<<` / `=======` / `>>>>>>>` three-way format. Jujutsu can materialize snapshot sections marked with `+++++++` and one or more diff sections marked with `%%%%%%%` inside the outer `<<<<<<< Conflict ...` and `>>>>>>> Conflict ... ends` markers. A conflict can have more than two sides, so understand every section before choosing the final content and removing the complete marker block.

After editing, verify both scopes again:

```bash
# Confirms whether the working-copy commit still has unresolved files
jj --no-pager status

# Must return no affected revisions for resolution to be complete across the stack
jj --no-pager log -r 'conflicts()'
```

`jj st` alone only describes `@`; a rebase can leave a conflict in another revision. Do not report conflict resolution complete while the relevant revision still appears in `conflicts()`.

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

## Megamerges (Multi-Branch Integration & Testing)

A **megamerge** is a local octopus merge commit whose parents are multiple in-flight WIP branches. It allows you to build, test, and run an entire application with multiple independent features applied simultaneously.

```
        (Combined working copy / tests)
                       │
                       ●  megamerge (octopus, local-only)
                     ╱ │ ╲
                    ●  ●  ●  feature-a, feature-b, feature-c
                     ╲ │ ╱
                       ●  trunk()
```

### 1. Creating a Megamerge

```bash
# Create an octopus merge commit across multiple branches
jj new feature-a feature-b feature-c -m "Local megamerge (test only)"

# Advance working copy on top of it
jj new
```

### 2. Testing & Propagating Changes

- Run test suites in the combined working copy to confirm that all branches compose cleanly.
- Use `jj absorb` to distribute fixes from `@` back into whichever parent feature branch last modified the affected lines:
```bash
jj absorb
```

### 3. Restacking onto Updated Trunk

When trunk updates, rebase all mutable branches in one command while collapsing redundant edges with `--simplify-parents`:

```bash
jj rebase --onto trunk() --source 'roots(trunk()..) & mutable()' --simplify-parents
```

### 4. Pushing from a Megamerge

**CRITICAL**: You never push the megamerge itself. Push each component bookmark individually:

```bash
jj git push -b feature-a
jj git push -b feature-b
```

## Preserving Commit Quality

**IMPORTANT**: Because commits are mutable, always refine them before considering work done:

1. **Review your commit**: `jj --no-pager show --git @` or `jj --no-pager diff --git`
2. **Is it atomic?** One logical change per commit
3. **Is the message clear?** Use imperative verb phrase in sentence case format with no full stop: e.g. "Add login endpoint", "Fix null pointer in payment processor", "Remove deprecated API endpoints"
4. **Are there unrelated changes?** Use `jj restore` to move changes out, then create separate commits
5. **Should changes be elsewhere?** Use `jj squash` or `jj absorb`
6. **Protect the completed commit**: Always run `jj new` when done so `@` is on a fresh empty revision rather than sitting directly on your finished commit

## Quick Reference

| Action | Command |
|--------|---------|
| Describe commit | `jj desc -m "message"` |
| View status | `jj --no-pager status` (or `jj --no-pager st`) |
| View log | `jj --no-pager log` |
| View diff | `jj --no-pager diff --git [paths]` |
| View commit diff | `jj --no-pager show --git <id>` |
| View unpushed commits | `jj --no-pager log -r 'remote_bookmarks()..'` |
| New commit | `jj new -m "message"` (check `jj --no-pager status` first; skip if `@` is empty) |
| Edit commit | `jj edit <id>` |
| Squash to parent | `jj squash` |
| Auto-distribute changes | `jj absorb` (or `jj absorb <paths>`) |
| Verify absorb / changes | `jj --no-pager op show -p` |
| Rebase | `jj rebase --onto <destination>` |
| Compare patch revisions | `jj --no-pager interdiff --from <old> --to <new> --git` |
| Parallelize revisions | `jj parallelize <revisions>` |
| Duplicate revision | `jj duplicate <id>` |
| Abandon commit | `jj abandon <id>` |
| Clean empty commits | `jj abandon 'empty() & mutable() & ~root() & ~@'` |
| Undo last operation | `jj undo` |
| Redo operation | `jj redo` |
| View operation log | `jj --no-pager op log -n 10` |
| Restore to operation | `jj op restore <operation-id>` |
| Inspect change evolution | `jj --no-pager evolog -p -r <change-id>` |
| Restore files | `jj restore [paths]` |
| List files at rev | `jj --no-pager file list -r <id>` |
| Show file content | `jj --no-pager file show -r <id> <path>` |
| Untrack ignored file | `jj file untrack <path>` (path must already be ignored) |
| Set / create bookmark | `jj bookmark set <name> -r <target>` |
| Rename bookmark | `jj bookmark rename <old> <new>` |
| Move bookmark backward/sideways | Inspect graph, then `jj bookmark set <name> -r <target> --allow-backwards` |
| Advance bookmark | `jj bookmark advance [-r <target>]` |
| Track remote bookmark | `jj bookmark track <name>@<remote>` |
| Untrack remote bookmark | `jj bookmark untrack <name>@<remote>` |
| Fetch remote | `jj git fetch` |
| Push bookmark | `jj git push -b <name>` |
| Push change ID | `jj git push -c <id>` |
| Add workspace | `jj workspace add <path>` |
| List workspaces | `jj --no-pager workspace list` |
| Forget workspace | `jj workspace forget [name]` |
| Fix stale working copy | `jj workspace update-stale` |
| List sparse patterns | `jj --no-pager sparse list` |
| Set sparse patterns | `jj sparse set --add <paths>` |

## Best Practices Summary

1. **Describe first**: Set the commit message before coding
2. **One change per commit**: Keep commits atomic and focused
3. **Use change IDs**: They're stable across rewrites
4. **Refine commits**: Leverage mutability for clean history
5. **Embrace the workflow**: No staging area, no stashing - just commits
6. **Always finish with `jj new`**: Protect completed work by advancing `@` to a new empty revision
