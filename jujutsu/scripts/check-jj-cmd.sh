#!/usr/bin/env python3
"""PreToolUse guardrail hook for Jujutsu (jj) agent workflows.

Supports:
  1. Antigravity PreToolUse hook (stdin JSON with .toolCall.args.CommandLine)
  2. Claude Code PreToolUse hook (stdin JSON with .tool_input.command)
  3. Direct CLI mode: check-jj-cmd.sh "<command>"
"""

import json
from pathlib import Path
import re
import shlex
import sys

OUTPUT_SUBCOMMANDS = {
    ("status",),
    ("st",),
    ("log",),
    ("diff",),
    ("show",),
    ("interdiff",),
    ("evolog",),
    ("evolution-log",),
    ("root",),
    ("help",),
    ("op", "log"),
    ("op", "show"),
    ("op", "diff"),
    ("operation", "log"),
    ("operation", "show"),
    ("operation", "diff"),
    ("file", "list"),
    ("file", "show"),
    ("file", "search"),
    ("file", "annotate"),
    ("config", "list"),
    ("config", "l"),
    ("config", "get"),
    ("config", "g"),
    ("config", "path"),
    ("config", "p"),
    ("bookmark", "list"),
    ("bookmark", "l"),
    ("b", "list"),
    ("b", "l"),
    ("tag", "list"),
    ("tag", "l"),
    ("workspace", "list"),
    ("workspace", "root"),
    ("sparse", "list"),
    ("git", "root"),
    ("git", "remote", "list"),
    ("git", "colocation", "status"),
}

GLOBAL_VALUE_FLAGS = {
    "-R",
    "--repository",
    "--at-op",
    "--at-operation",
    "--color",
    "--config",
    "--config-file",
}

ENV_ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def is_jj_repo() -> bool:
    try:
        cwd = Path.cwd().resolve()
    except OSError:
        return False
    return any((p / ".jj").exists() for p in (cwd, *cwd.parents))


def is_cmd_name(token: str, name: str) -> bool:
    return token == name or token.endswith(f"/{name}")


def split_shell_tokens(command: str) -> list[str] | None:
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lexer.whitespace_split = True
        return list(lexer)
    except ValueError:
        return None


def validate_command(cmd: str) -> str | None:
    stripped = cmd.strip()
    if not stripped:
        return None

    # Check shell wrappers around jj before tokenizing
    if re.search(r"\$\(\s*jj\b|`\s*jj\b", stripped):
        return (
            "Do not wrap 'jj' in command substitution ($() or backticks); "
            "it breaks Bash(jj *) permissions. Run jj directly and pass literal output."
        )
    if re.search(r"(?:^|[;&|]+)\s*cd\s+[^;&|]+[;&|]+\s*jj\b", stripped):
        return (
            "Do not chain 'cd <dir> && jj ...'; it breaks Bash(jj *) and fails across "
            "stateless shell calls. Use 'jj -R <workspace-path> ...' instead."
        )

    raw_tokens = split_shell_tokens(stripped)
    if not raw_tokens:
        return None

    # Split into simple command segments separated by ;, &, &&, |, ||
    segments: list[list[str]] = []
    separators: list[str] = []
    current: list[str] = []
    for tok in raw_tokens:
        if set(tok) <= {";", "&", "|"}:
            separators.append(tok)
            if current:
                segments.append(current)
                current = []
        else:
            current.append(tok)
    if current:
        segments.append(current)

    if not segments:
        return None

    has_cd_segment = False
    jj_segment_info: tuple[list[str], list[str]] | None = None
    has_git_segment = False

    for seg in segments:
        env_prefix: list[str] = []
        idx = 0
        while idx < len(seg) and ENV_ASSIGNMENT_RE.match(seg[idx]):
            env_prefix.append(seg[idx])
            idx += 1
        cmd_tokens = seg[idx:]
        if not cmd_tokens:
            continue
        head = cmd_tokens[0]
        if head == "cd":
            has_cd_segment = True
        elif is_cmd_name(head, "jj") and jj_segment_info is None:
            jj_segment_info = (env_prefix, cmd_tokens)
        elif is_cmd_name(head, "git"):
            has_git_segment = True

    if jj_segment_info is not None:
        env_prefix, tokens = jj_segment_info
        if separators:
            if has_cd_segment:
                return (
                    "Do not chain 'cd <dir>' with 'jj'; it breaks Bash(jj *) and fails across "
                    "stateless shell calls. Use 'jj -R <workspace-path> ...' instead."
                )
            op = separators[0]
            return (
                f"Do not chain or pipe 'jj' commands with '{op}'; compound commands "
                "fall outside Bash(jj *). Use native jj flags (-n, -r, -T, -R, jj commit -m)."
            )
        if env_prefix:
            return (
                "Do not prefix 'jj' with inline environment variable assignments "
                f"('{env_prefix[0]} jj ...'); it breaks Bash(jj *) permissions."
            )
    else:
        if has_git_segment and is_jj_repo():
            return (
                "This is a Jujutsu (.jj) repository. Do not run raw 'git' commands "
                "(they fall outside Bash(jj *) and can corrupt colocated state); "
                "use 'jj' equivalents instead."
            )
        return None

    # Parse global flags vs subcommand
    has_no_pager = False
    has_color_never = False
    has_help = False
    i = 1
    sub_idx = None

    while i < len(tokens):
        tok = tokens[i]
        if tok == "--no-pager":
            has_no_pager = True
            i += 1
        elif tok.startswith("--color="):
            color_val = tok.split("=", 1)[1]
            if color_val != "never":
                return (
                    "Always use '--color=never' (never '--color=always' or '--color=auto') "
                    "so captured output is not wrapped in ANSI codes."
                )
            has_color_never = True
            i += 1
        elif tok == "--color" and i + 1 < len(tokens):
            if tokens[i + 1] != "never":
                return (
                    "Always use '--color=never' (never '--color=always' or '--color=auto') "
                    "so captured output is not wrapped in ANSI codes."
                )
            has_color_never = True
            i += 2
        elif tok in ("-h", "--help", "-V", "--version"):
            if tok in ("-h", "--help"):
                has_help = True
            i += 1
        elif tok == "--ignore-immutable":
            return (
                "NEVER pass '--ignore-immutable'. Create a new change with 'jj new <base>' "
                "or rebase mutable commits onto the immutable head."
            )
        elif tok == "--allow-cross-workspace":
            return (
                "Do not pass '--allow-cross-workspace'; it can revert work in another workspace."
            )
        elif tok in GLOBAL_VALUE_FLAGS or any(
            tok.startswith(f + "=") for f in GLOBAL_VALUE_FLAGS
        ):
            val = (
                tok.split("=", 1)[1]
                if "=" in tok
                else (tokens[i + 1] if i + 1 < len(tokens) else "")
            )
            if any(k in val for k in ("signing.behavior", "git-sign-on-push", "sign-on-push")):
                return (
                    "Do not override signing configuration ('signing.behavior' or 'revsets.git-sign-on-push'); stop and report signing errors."
                )
            i += 1 if "=" in tok else 2
        elif tok.startswith("-"):
            i += 1
        else:
            sub_idx = i
            break

    if sub_idx is None:
        if any(t in ("-V", "--version") for t in tokens[1:]):
            return None
        return (
            "Never invoke bare 'jj' without an explicit subcommand; "
            "pass '--no-pager --color=never <subcommand>'."
        )

    rest = tokens[sub_idx:]
    sub1 = rest[0]
    sub2 = rest[1] if len(rest) > 1 and not rest[1].startswith("-") else None
    sub3 = (
        rest[2]
        if sub2 is not None and len(rest) > 2 and not rest[2].startswith("-")
        else None
    )
    args = rest[1:]

    # Global ban on forbidden flags anywhere in args
    for idx, arg in enumerate(args):
        if arg == "--ignore-immutable":
            return (
                "NEVER pass '--ignore-immutable'. Branch off with 'jj new <base>' "
                "or rebase mutable commits."
            )
        if arg == "--allow-cross-workspace":
            return (
                "Do not pass '--allow-cross-workspace'; it can revert work in another workspace."
            )
        if arg == "--no-pager":
            has_no_pager = True
        if arg.startswith("--color="):
            color_val = arg.split("=", 1)[1]
            if color_val != "never":
                return (
                    "Always use '--color=never' (never '--color=always' or '--color=auto') "
                    "so captured output is not wrapped in ANSI codes."
                )
            has_color_never = True
        if arg == "--color" and idx + 1 < len(args):
            if args[idx + 1] != "never":
                return (
                    "Always use '--color=never' (never '--color=always' or '--color=auto') "
                    "so captured output is not wrapped in ANSI codes."
                )
            has_color_never = True
        if arg == "--color-words":
            return (
                "Do not pass '--color-words'; under '--color=never' it omits +/- markers "
                "and makes additions and deletions indistinguishable. Use '--git' instead."
            )
        if arg in ("-i", "--interactive", "--editor", "--tool") or arg.startswith("--tool="):
            return (
                f"Never pass '{arg}'; interactive prompts and external editors hang agent sessions."
            )
        if arg in ("-m", "--message") and idx + 1 < len(args) and args[idx + 1].startswith("-"):
            return (
                "Message text starting with '-' after '-m' is parsed as a CLI flag by jj. "
                "Use '-m=\"- ...\"' or '--message=\"- ...\"' instead."
            )
        if arg in ("--config", "--config-toml") or arg.startswith("--config="):
            val = (
                arg.split("=", 1)[1]
                if "=" in arg
                else (args[idx + 1] if idx + 1 < len(args) else "")
            )
            if any(k in val for k in ("signing.behavior", "git-sign-on-push", "sign-on-push")):
                return (
                    "Do not override signing configuration ('signing.behavior' or 'revsets.git-sign-on-push'); stop and report signing errors."
                )
        if arg in ("-h", "--help"):
            has_help = True

    if sub1 == "unsign" and not has_help:
        return (
            "Do not run 'jj unsign' to drop cryptographic signatures; "
            "stop and report signing errors."
        )

    # Subcommand-specific interactive checks
    if (
        sub1 in ("diffedit", "resolve", "arrange")
        or (sub1 == "file" and sub2 == "edit")
        or (sub1 == "config" and sub2 in ("edit", "e"))
    ):
        if sub1 == "file":
            cmd_name = "jj file edit"
        elif sub1 == "config":
            cmd_name = f"jj config {sub2}"
        else:
            cmd_name = f"jj {sub1}"
        return (
            f"Do not run '{cmd_name}'; it launches an interactive TUI, editor, or merge tool. "
            "Edit files directly or use non-interactive jj commands."
        )

    if sub1 == "converge" and "--no-interactive" not in args:
        return "Always pass '--no-interactive' to 'jj converge'."

    def has_msg_flag(arg_list: list[str]) -> bool:
        return any(
            a in ("-m", "--message", "--stdin")
            or a.startswith("-m")
            or a.startswith("--message=")
            for a in arg_list
        )

    if sub1 in ("desc", "describe") and not has_help and not has_msg_flag(args):
        return "Always pass '-m \"...\"' to 'jj desc' to avoid opening an interactive editor."

    if sub1 in ("commit", "ci") and not has_help and not has_msg_flag(args):
        return f"Always pass '-m \"...\"' to 'jj {sub1}' to avoid opening an interactive editor."

    if sub1 == "squash" and not has_help:
        has_u = any(a in ("-u", "--use-destination-message") for a in args)
        if not (has_u or has_msg_flag(args)):
            return "Always pass '-u' or '-m \"...\"' to 'jj squash' to avoid opening an editor."

    if sub1 == "split" and not has_help:
        if not has_msg_flag(args):
            return "Always pass '-m \"...\"' and explicit file paths to 'jj split'."
        skip_next = False
        positional = []
        value_flags = {
            "-r", "--revision", "-o", "--onto", "-d", "--destination",
            "-A", "--insert-after", "--after", "-B", "--insert-before", "--before",
            "-m", "--message",
            *GLOBAL_VALUE_FLAGS,
        }
        for a in args:
            if skip_next:
                skip_next = False
                continue
            if a in value_flags:
                skip_next = True
            elif a.startswith("-"):
                continue
            else:
                positional.append(a)
        if not positional:
            return "Always pass explicit file path(s) to 'jj split' so it does not open a diff editor."

    if sub1 == "revert" and not has_help:
        rev_flags = ("-r", "--revision", "--revisions")
        dest_flags = (
            "-o", "--onto", "-d", "--destination",
            "-A", "--insert-after", "--after",
            "-B", "--insert-before", "--before",
        )
        has_rev = any(
            a in rev_flags
            or a.startswith("-r")
            or any(a.startswith(f + "=") for f in rev_flags)
            for a in args
        )
        has_dest = any(
            a in dest_flags
            or any(a.startswith(f + "=") for f in dest_flags)
            for a in args
        )
        if not (has_rev and has_dest):
            return (
                "Always pass both '-r <revset>' and a destination flag "
                "('--onto', '-A', or '-B') to 'jj revert' (e.g. 'jj revert -r <id> --onto @')."
            )

    if sub1 == "interdiff" and not has_help:
        endpoint_flags = ("-f", "--from", "-t", "--to")
        if not any(
            a in endpoint_flags
            or a.startswith(("-f", "-t"))
            or any(a.startswith(f + "=") for f in endpoint_flags)
            for a in args
        ):
            return "Always pass '--from <rev>' and/or '--to <rev>' to 'jj interdiff'."

    if sub1 == "file" and sub2 == "search" and not has_help:
        search_args = rest[2:]
        if not any(
            a in ("-p", "--pattern")
            or a.startswith("-p")
            or a.startswith("--pattern=")
            for a in search_args
        ):
            return (
                "Always pass '-p <pattern>' (or '--pattern <pattern>') to 'jj file search' "
                "(positional arguments are fileset paths)."
            )

    if sub1 == "git" and sub2 == "push" and not has_help:
        push_args = rest[2:]
        explicit_push_flags = (
            "-b", "--bookmark", "-c", "--change", "-r", "--revisions",
            "--named", "--all", "--tracked", "--deleted",
        )
        if not any(
            a in explicit_push_flags
            or any(a.startswith(f + "=") for f in explicit_push_flags)
            for a in push_args
        ):
            return (
                "Do not run bare 'jj git push'; pass an explicit target such as "
                "'-b <bookmark>' or '-c <change-id>'."
            )

    # Check --no-pager and --color=never for output-producing commands
    is_output_cmd = (
        has_help
        or (sub1,) in OUTPUT_SUBCOMMANDS
        or (sub2 is not None and (sub1, sub2) in OUTPUT_SUBCOMMANDS)
        or (
            sub2 is not None
            and sub3 is not None
            and (sub1, sub2, sub3) in OUTPUT_SUBCOMMANDS
        )
    )
    if is_output_cmd and not (has_no_pager and has_color_never):
        return (
            "Always pass '--no-pager --color=never' to output-producing jj commands "
            "(status, log, diff, show, interdiff, evolog, root, op log/show/diff, "
            "file list/show/search/annotate, config list/get/path, bookmark/tag list, "
            "workspace list/root, sparse list, git root/remote list/colocation status, --help)."
        )

    # Check --git or --stat on diff/show/interdiff, op diff, and -p/--patch commands
    has_patch_flag = any(a in ("-p", "--patch") for a in args)
    needs_diff_format = (
        sub1 in ("diff", "show", "interdiff")
        or (sub1 in ("op", "operation") and sub2 == "diff")
        or (
            has_patch_flag
            and (
                sub1 in ("log", "evolog", "evolution-log")
                or (sub1 in ("op", "operation") and sub2 in ("show", "log"))
            )
        )
    )
    if needs_diff_format and not has_help:
        diff_format_flags = ("--git", "--stat", "--summary", "-s", "--name-only", "--types")
        if not any(a in diff_format_flags for a in args):
            target_cmd = f"jj {sub1} {sub2}" if sub1 in ("op", "operation") and sub2 else f"jj {sub1}"
            return (
                f"Always pass '--git' (or '--stat') to '{target_cmd}' when rendering diffs "
                "to bypass external diff formatters and side-by-side output."
            )

    return None


def main() -> int:
    # Mode 1: Direct CLI invocation: check-jj-cmd.sh "<command>"
    if len(sys.argv) > 1:
        reason = validate_command(sys.argv[1])
        if reason:
            sys.stderr.write(f"Blocked jj command: {reason}\n")
            return 2
        return 0

    # Read stdin JSON for hook invocations
    raw = sys.stdin.read().strip()
    if not raw:
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return 0

    # Mode 2: Antigravity PreToolUse contract (.toolCall.args.CommandLine)
    if "toolCall" in payload:
        tool_call = payload.get("toolCall") or {}
        args = tool_call.get("args") or {}
        cmd = args.get("CommandLine") or ""
        reason = validate_command(cmd)
        if reason:
            print(json.dumps({"decision": "deny", "reason": reason}))
        else:
            print(json.dumps({"decision": "allow"}))
        return 0

    # Mode 3: Claude Code PreToolUse contract (.tool_input.command)
    tool_input = payload.get("tool_input") or {}
    cmd = tool_input.get("command") or ""
    reason = validate_command(cmd)
    if reason:
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                }
            )
        )
        sys.stderr.write(f"{reason}\n")
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
