#!/bin/bash

# Script to set up git hooks for the project

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Setting up git hooks for Parrot Platform..."

# Configure git to use the .githooks directory
git config core.hooksPath .githooks

if [ $? -eq 0 ]; then
    echo "✓ Git hooks configured successfully"
    echo "  Pre-push hook will check code formatting before pushing"
else
    echo "✗ Failed to configure git hooks"
    exit 1
fi

# Verify the hooks are executable
if [ -x "$PROJECT_ROOT/.githooks/pre-push" ]; then
    echo "✓ Pre-push hook is executable"
else
    echo "⚠ Making pre-push hook executable..."
    chmod +x "$PROJECT_ROOT/.githooks/pre-push"
fi

echo ""
echo "Setup complete! The following hooks are now active:"
echo "  - pre-push: Checks code formatting with 'mix format'"
echo ""
echo "To bypass hooks temporarily, use: git push --no-verify"