set default-list := true

install: install-claude install-antigravity

install-claude:
    mkdir -p ~/.claude/skills/jujutsu
    cp -R ./jujutsu/. ~/.claude/skills/jujutsu/

install-antigravity:
    mkdir -p ~/.gemini/config/skills/jujutsu
    cp -R ./jujutsu/. ~/.gemini/config/skills/jujutsu/

install-local: install-local-claude install-local-antigravity

install-local-claude:
    mkdir -p .claude/skills/jujutsu
    cp -R ./jujutsu/. .claude/skills/jujutsu/

install-local-antigravity:
    mkdir -p .agents/skills/jujutsu
    cp -R ./jujutsu/. .agents/skills/jujutsu/

uninstall:
    rm -rf ~/.claude/skills/jujutsu ~/.gemini/config/skills/jujutsu

uninstall-local:
    rm -rf .claude/skills/jujutsu .agents/skills/jujutsu

check: check-patterns check-sync

check-patterns:
    @echo "Checking SKILL.md and README.md for interactive or un-guarded commands..."
    @! grep -E "^[[:space:]]*jj (squash|split|diff|diffedit|restore|absorb) -i\b" jujutsu/SKILL.md README.md
    @! grep -E "^[[:space:]]*jj (file edit|resolve)\b" jujutsu/SKILL.md README.md
    @! grep -E "^[[:space:]]*jj (status|st|diff|show|log)\b" jujutsu/SKILL.md README.md
    @! grep -E "^[[:space:]]*jj squash[[:space:]]*$$" jujutsu/SKILL.md README.md
    @echo "All pattern checks passed."

check-sync:
    @echo "Checking sync with global installs..."
    @if [ -d ~/.gemini/config/skills/jujutsu ]; then diff -ru jujutsu/ ~/.gemini/config/skills/jujutsu/ || (echo "Antigravity skill out of sync. Run 'just install-antigravity'" && exit 1); fi
    @if [ -d ~/.claude/skills/jujutsu ]; then diff -ru jujutsu/ ~/.claude/skills/jujutsu/ || (echo "Claude skill out of sync. Run 'just install-claude'" && exit 1); fi
    @echo "All installed skills are in sync."
