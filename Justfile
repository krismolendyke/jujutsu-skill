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

check: check-patterns check-sync

check-patterns:
    @echo "Checking SKILL.md and README.md for interactive or un-guarded commands..."
    @! grep -nE "^[[:space:]]*jj (squash|split|diff|diffedit|restore|absorb) -i\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (file edit|resolve)\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (-R [^[:space:]]+ )?(status|st|diff|show|log|interdiff|evolog|op (log|show)|file (list|show)|config (list|get)|bookmark list|workspace (list|root)|sparse list)\b" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj (squash|converge|git push)[[:space:]]*$" jujutsu/SKILL.md README.md
    @! grep -nE "^[[:space:]]*jj --no-pager --color=never (diff|show|interdiff)\b" jujutsu/SKILL.md README.md | grep -vE "(--git|--stat)"
    @! grep -nE "^[[:space:]]*jj [^#]*(\|\||&&|\|[[:space:]]*(head|tail|grep|rg|awk|sed|wc|sort|less|more|cat|xargs)\b)" jujutsu/SKILL.md README.md
    @test "$(wc -l < jujutsu/SKILL.md)" -lt 800 || (echo "jujutsu/SKILL.md exceeds 800-line single-read limit" && exit 1)
    @echo "All pattern checks passed."

check-sync:
    @echo "Checking sync with global installs..."
    @if [ -d ~/.gemini/config/skills/jujutsu ]; then diff -ru jujutsu/ ~/.gemini/config/skills/jujutsu/ || (echo "Antigravity config skill out of sync. Run 'just install-antigravity'" && exit 1); fi
    @if [ -d ~/.gemini/skills/jujutsu ]; then diff -ru jujutsu/ ~/.gemini/skills/jujutsu/ || (echo "Antigravity skill out of sync. Run 'just install-antigravity'" && exit 1); fi
    @if [ -d ~/.claude/skills/jujutsu ]; then diff -ru jujutsu/ ~/.claude/skills/jujutsu/ || (echo "Claude skill out of sync. Run 'just install-claude'" && exit 1); fi
    @echo "All installed skills are in sync."
