#!/bin/bash
# Git Email Guard - Claude Code hook to prevent commits with wrong email
# Warns about email mismatches based on repository remote URL patterns

CONFIG_FILE="${GIT_EMAIL_GUARD_CONFIG:-$HOME/.claude/git-email-rules.json}"

# Get the command from stdin (Claude Code hook receives tool input as JSON)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.command // ""' 2>/dev/null)

# Only check git commit/push commands
if [[ ! "$COMMAND" =~ (git\ commit|git\ push) ]]; then
    exit 0
fi

# Create default config if missing
if [ ! -f "$CONFIG_FILE" ]; then
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" << 'EOF'
{
  "rules": [
    {
      "pattern": "github.com/your-username",
      "email": "personal@example.com",
      "context": "Personal GitHub"
    },
    {
      "pattern": "github.com/work-org",
      "email": "work@company.com",
      "context": "Work GitHub"
    },
    {
      "pattern": "bitbucket.org",
      "email": "work@company.com",
      "context": "Work Bitbucket"
    }
  ],
  "default_email": null
}
EOF
    echo "⚙️  Created default config at: $CONFIG_FILE"
    echo "📝 Please edit it to match your repositories!"
    exit 0
fi

# Get current git config
REPO_EMAIL=$(git config user.email 2>/dev/null)
REPO_NAME=$(git config user.name 2>/dev/null)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "no remote")

# Find matching rule
EXPECTED_EMAIL=""
CONTEXT=""
while IFS= read -r rule; do
    pattern=$(echo "$rule" | jq -r '.pattern')
    if [[ "$REMOTE_URL" == *"$pattern"* ]]; then
        EXPECTED_EMAIL=$(echo "$rule" | jq -r '.email')
        CONTEXT=$(echo "$rule" | jq -r '.context')
        break
    fi
done < <(jq -c '.rules[]' "$CONFIG_FILE" 2>/dev/null)

# Check for mismatch
if [ -n "$EXPECTED_EMAIL" ] && [ "$EXPECTED_EMAIL" != "null" ] && [ "$REPO_EMAIL" != "$EXPECTED_EMAIL" ]; then
    cat << EOF
<git-email-warning>
⚠️  GIT EMAIL MISMATCH DETECTED

📍 Repo: $(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
🔗 Remote: $REMOTE_URL
👤 Current email: $REPO_EMAIL
✅ Expected email: $EXPECTED_EMAIL ($CONTEXT)

To fix: git config user.email "$EXPECTED_EMAIL"
Config: $CONFIG_FILE
</git-email-warning>
EOF
fi

# Always show context for commits
if [[ "$COMMAND" =~ git\ commit ]]; then
    cat << EOF
<git-commit-context>
📝 Committing as: $REPO_NAME <$REPO_EMAIL>
🔗 To: $(echo "$REMOTE_URL" | sed 's/.*[:/]\([^/]*\/[^/]*\)\.git/\1/' || echo "$REMOTE_URL")
</git-commit-context>
EOF
fi

exit 0
