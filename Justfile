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
