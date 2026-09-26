set default-list := true

install: install-claude install-antigravity

install-claude:
    mkdir -p ~/.claude/skills/jujutsu
    cp -R ./jujutsu/. ~/.claude/skills/jujutsu/

install-antigravity:
    mkdir -p ~/.gemini/config/skills/jujutsu
    cp -R ./jujutsu/. ~/.gemini/config/skills/jujutsu/
