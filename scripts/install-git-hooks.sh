#!/bin/bash
# Script to install git hooks for automatic code formatting

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$PROJECT_ROOT/.git/hooks"
GIT_HOOKS_SOURCE="$SCRIPT_DIR/git-hooks"

echo "🔧 Installing git hooks..."

# Check if .git directory exists
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "❌ Error: .git directory not found. Are you in a git repository?"
    exit 1
fi

# Create hooks directory if it doesn't exist
mkdir -p "$HOOKS_DIR"

# Install pre-commit hook
if [ -f "$GIT_HOOKS_SOURCE/pre-commit" ]; then
    cp "$GIT_HOOKS_SOURCE/pre-commit" "$HOOKS_DIR/pre-commit"
    chmod +x "$HOOKS_DIR/pre-commit"
    echo "✅ Installed pre-commit hook"
else
    echo "⚠️  Warning: pre-commit hook not found in $GIT_HOOKS_SOURCE"
fi

# Install pre-push hook
if [ -f "$GIT_HOOKS_SOURCE/pre-push" ]; then
    cp "$GIT_HOOKS_SOURCE/pre-push" "$HOOKS_DIR/pre-push"
    chmod +x "$HOOKS_DIR/pre-push"
    echo "✅ Installed pre-push hook"
else
    echo "⚠️  Warning: pre-push hook not found in $GIT_HOOKS_SOURCE"
fi

echo ""
echo "✅ Git hooks installed successfully!"
echo ""
echo "📋 Installed hooks:"
echo "   - pre-commit: Automatically formats code before commit"
echo "   - pre-push: Checks code format before push (safety net)"
echo ""
echo "💡 These hooks will ensure your code is always formatted before committing/pushing."

