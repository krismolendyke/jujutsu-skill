#!/usr/bin/env python3
"""PreToolUse guardrail hook for Jujutsu (jj) agent workflows.

Supports:
  1. Antigravity PreToolUse hook (stdin JSON with .toolCall.args.CommandLine)
  2. Claude Code PreToolUse hook (stdin JSON with .tool_input.command)
  3. Direct CLI mode: check-jj-cmd.sh "<command>"
"""

import json
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
    ("op", "log"),
    ("op", "show"),
    ("file", "list"),
    ("file", "show"),
    ("config", "list"),
    ("config", "get"),
    ("bookmark", "list"),
    ("workspace", "list"),
    ("workspace", "root"),
    ("sparse", "list"),
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
    if re.search(r"(?:^|[;&|]+)\s*cd\s+[^;&|]+&&\s*jj\b", stripped):
        return (
            "Do not chain 'cd <dir> && jj ...'; it breaks Bash(jj *) and fails across "
            "stateless shell calls. Use 'jj -R <workspace-path> ...' instead."
        )

    try:
        tokens = shlex.split(stripped)
    except ValueError:
        return None

    if not tokens or tokens[0] != "jj":
        return None

    # Reject compound shell operators in a jj command line
    for op in ("&&", "||", ";", "|"):
        if op in tokens:
            return (
                f"Do not chain or pipe 'jj' commands with '{op}'; compound commands "
                "fall outside Bash(jj *). Use native jj flags (-n, -r, -T, -R, jj commit -m)."
            )

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
        elif tok == "--color=never":
            has_color_never = True
            i += 1
        elif tok == "--color" and i + 1 < len(tokens):
            if tokens[i + 1] == "never":
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
            if "signing.behavior" in val:
                return "Do not override 'signing.behavior'; stop and report signing errors."
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
        if arg in ("-i", "--interactive", "--editor", "--tool") or arg.startswith("--tool="):
            return (
                f"Never pass '{arg}'; interactive prompts and external editors hang agent sessions."
            )
        if arg in ("--config", "--config-toml") or arg.startswith("--config="):
            val = (
                arg.split("=", 1)[1]
                if "=" in arg
                else (args[idx + 1] if idx + 1 < len(args) else "")
            )
            if "signing.behavior" in val:
                return "Do not override 'signing.behavior'; stop and report signing errors."
        if arg in ("-h", "--help"):
            has_help = True

    # Subcommand-specific interactive checks
    if sub1 == "diffedit" or sub1 == "resolve" or (sub1 == "file" and sub2 == "edit"):
        cmd_name = f"jj {sub1}" if sub1 != "file" else "jj file edit"
        return (
            f"Do not run '{cmd_name}'; it launches an interactive editor/merge tool. "
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

    if sub1 == "commit" and not has_help and not has_msg_flag(args):
        return "Always pass '-m \"...\"' to 'jj commit' to avoid opening an interactive editor."

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
            "-A", "--insert-after", "-B", "--insert-before", "-m", "--message",
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
    )
    if is_output_cmd and not (has_no_pager and has_color_never):
        return (
            "Always pass '--no-pager --color=never' to output-producing jj commands "
            "(status, log, diff, show, interdiff, evolog, op log/show, file list/show, "
            "config list/get, bookmark list, workspace list/root, sparse list, --help)."
        )

    # Check --git or --stat on diff/show/interdiff
    if sub1 in ("diff", "show", "interdiff") and not has_help:
        diff_format_flags = ("--git", "--stat", "--summary", "-s", "--name-only", "--types")
        if not any(a in diff_format_flags for a in args):
            return (
                f"Always pass '--git' (or '--stat') to 'jj {sub1}' to bypass external "
                "diff formatters and side-by-side output."
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
