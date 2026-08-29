set default-list := true

install: install-claude install-antigravity

install-claude:
    mkdir -p ~/.claude/skills
    cp -r ./jujutsu ~/.claude/skills/jujutsu

install-antigravity:
    mkdir -p ~/.gemini/config/skills
    cp -r ./jujutsu ~/.gemini/config/skills/jujutsu
