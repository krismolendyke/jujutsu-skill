set default-list := true

install: install-claude install-antigravity

install-claude:
    mkdir -p ~/.claude/skills/jujutsu
    cp -R ./jujutsu/. ~/.claude/skills/jujutsu/

install-antigravity:
    mkdir -p ~/.gemini/config/skills/jujutsu ~/.gemini/skills/jujutsu
    cp -R ./jujutsu/. ~/.gemini/config/skills/jujutsu/
    cp -R ./jujutsu/. ~/.gemini/skills/jujutsu/

install-local: install-local-claude install-local-antigravity

install-local-claude:
    mkdir -p .claude/skills/jujutsu
    cp -R ./jujutsu/. .claude/skills/jujutsu/

install-local-antigravity:
    mkdir -p .agents/skills/jujutsu
    cp -R ./jujutsu/. .agents/skills/jujutsu/

uninstall:
    rm -rf ~/.claude/skills/jujutsu ~/.gemini/config/skills/jujutsu ~/.gemini/skills/jujutsu

uninstall-local:
    rm -rf .claude/skills/jujutsu .agents/skills/jujutsu

check: check-patterns check-hook check-sync

check-patterns:
    @echo "Checking SKILL.md and README.md for interactive or un-guarded commands..."
    @! grep -nE "^[[:space:]]*jj (squash|split|diff|diffedit|restore|absorb) -i\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (file edit|config edit|resolve|arrange)\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (-R [^[:space:]]+ )?(status|st|diff|show|log|interdiff|evolog|evolution-log|root|op (log|show|diff)|operation (log|show|diff)|file (list|show|search|annotate)|config (list|get|path)|bookmark list|tag list|workspace (list|root)|sparse list)\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (squash|converge|git push)[[:space:]]*$" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj --no-pager --color=never (diff|show|interdiff|op diff|operation diff)\b" jujutsu/SKILL.md README.md | grep -vE "(--git|--stat)"
    @! grep -nE "^[[:space:]]*jj --no-pager --color=never (log|evolog|evolution-log|op (show|log)|operation (show|log))\b[^#]*[[:space:]](-p|--patch)\b" jujutsu/SKILL.md README.md | grep -vE "(--git|--stat)"
    @! grep -nE "^[[:space:]]*jj [^#]*(--ignore-immutable|--allow-cross-workspace)" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj [^#]*(\|\||&&|\|[[:space:]]*(head|tail|grep|rg|awk|sed|wc|sort|less|more|cat|xargs)\b)" jujutsu/SKILL.md README.md
    @test "$(wc -l < jujutsu/SKILL.md)" -lt 800 || (echo "jujutsu/SKILL.md exceeds 800-line single-read limit" && exit 1)
    @echo "All pattern checks passed."

check-hook:
    @echo "Testing jujutsu/scripts/check-jj-cmd.sh..."
    @chmod +x jujutsu/scripts/check-jj-cmd.sh
    @./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never status"
    @./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never -R .jj-workspaces/agent-db diff --git"
    @./jujutsu/scripts/check-jj-cmd.sh "jj desc -m 'Fix jj resolve and -i handling in status'"
    @./jujutsu/scripts/check-jj-cmd.sh "jj desc -m='- Bullet item with leading hyphen'"
    @./jujutsu/scripts/check-jj-cmd.sh "jj split -r @ -m 'Split file' path/to/file.txt"
    @./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never file search -r @ pattern"
    @./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never log -p --git"
    @./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never op show -p --git"
    @./jujutsu/scripts/check-jj-cmd.sh "jj revert -r @- --onto @"
    @./jujutsu/scripts/check-jj-cmd.sh "npm test"
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj status" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never diff" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never log -p" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never op show -p" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj --no-pager --color=never op diff" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj squash -i" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj resolve" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj arrange" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj file edit foo.txt" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj config edit --user" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj ci" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj desc -m '- Unattached leading hyphen'" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj split --after @- -m 'Missing fileset'" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj revert -r @-" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj rebase --ignore-immutable --onto main" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj undo --allow-cross-workspace" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj file search pattern" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj --config 'revsets.git-sign-on-push=\"none()\"' git push -b feat" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "cd .jj-workspaces/agent-db && jj --no-pager --color=never status" 2>/dev/null
    @! ./jujutsu/scripts/check-jj-cmd.sh "jj git push" 2>/dev/null
    @echo '{"toolCall":{"name":"run_command","args":{"CommandLine":"jj squash -i"}}}' | ./jujutsu/scripts/check-jj-cmd.sh | grep -q '"decision": "deny"'
    @echo '{"toolCall":{"name":"run_command","args":{"CommandLine":"jj --no-pager --color=never status"}}}' | ./jujutsu/scripts/check-jj-cmd.sh | grep -q '"decision": "allow"'
    @! (echo '{"tool_input":{"command":"jj squash -i"}}' | ./jujutsu/scripts/check-jj-cmd.sh >/dev/null 2>&1)
    @echo "All hook checks passed."

check-sync:
    @echo "Checking sync with global installs..."
    @if [ -d ~/.gemini/config/skills/jujutsu ]; then diff -ru jujutsu/ ~/.gemini/config/skills/jujutsu/ || (echo "Antigravity config skill out of sync. Run 'just install-antigravity'" && exit 1); fi
    @if [ -d ~/.gemini/skills/jujutsu ]; then diff -ru jujutsu/ ~/.gemini/skills/jujutsu/ || (echo "Antigravity skill out of sync. Run 'just install-antigravity'" && exit 1); fi
    @if [ -d ~/.claude/skills/jujutsu ]; then diff -ru jujutsu/ ~/.claude/skills/jujutsu/ || (echo "Claude skill out of sync. Run 'just install-claude'" && exit 1); fi
    @echo "All installed skills are in sync."
