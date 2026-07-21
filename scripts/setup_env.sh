#!/usr/bin/env bash
# setup_env.sh - Install opencode, gitcode CLI, copy skills, and generate opencode config.
#
# Usage: bash scripts/setup_env.sh [skills_src_dir]
#   skills_src_dir  - Directory containing skill .md files (default: .claude/skills)
#
# Required environment variables:
#   BAILIAN_API_KEY - AI model API key (referenced via {env:}, never written to disk)
#   GC_TOKEN        - GitCode CLI token (for issue data collection)
set -euo pipefail

SKILLS_SRC_DIR="${1:-.claude/skills}"

echo "=== Install opencode CLI ==="
if ! command -v opencode &>/dev/null; then
    curl -fsSL https://opencode.ai/install | bash
    echo "$HOME/.opencode/bin" >> "$GITHUB_PATH"
    export PATH="$HOME/.opencode/bin:$PATH"
else
    echo "opencode already installed: $(opencode --version 2>&1 | head -1)"
fi

echo "=== Install gitcode CLI ==="
if ! command -v gc &>/dev/null; then
    GC_VERSION="0.8.0"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  GC_ARCH="amd64" ;;
        aarch64) GC_ARCH="arm64" ;;
        *)       GC_ARCH="$ARCH" ;;
    esac

    GC_DEB_URL="https://gitcode.com/gitcode-cli/cli/releases/download/v${GC_VERSION}/gc_${GC_VERSION}_${GC_ARCH}.deb"
    echo "Downloading: $GC_DEB_URL"
    curl -fsSL "$GC_DEB_URL" -o /tmp/gc.deb && sudo dpkg -i /tmp/gc.deb && {
        echo "gitcode CLI installed: $(gc version 2>&1 | head -1)"
    } || {
        echo "deb install failed, trying tar.gz..."
        GC_TGZ_URL="https://gitcode.com/gitcode-cli/cli/releases/download/v${GC_VERSION}/gc_linux_${GC_ARCH}.tar.gz"
        curl -fsSL "$GC_TGZ_URL" -o /tmp/gc.tar.gz || {
            echo "ERROR: cannot download gitcode CLI"
            exit 1
        }
        mkdir -p /tmp/gc-extract
        tar -xzf /tmp/gc.tar.gz -C /tmp/gc-extract
        sudo cp /tmp/gc-extract/gc /usr/local/bin/gc
        sudo chmod +x /usr/local/bin/gc
        echo "gitcode CLI installed (tar.gz): $(gc version 2>&1 | head -1)"
    }
else
    echo "gitcode CLI already installed: $(gc version 2>&1 | head -1)"
fi

echo "=== Configure GitCode CLI auth ==="
if [[ -n "${GC_TOKEN:-}" ]]; then
    gc auth login --token "$GC_TOKEN" 2>&1 || echo "WARNING: gc auth login failed (may already be logged in)"
else
    echo "WARNING: GC_TOKEN not set"
fi

echo "=== Copy skills to ~/.claude/skills/ ==="
mkdir -p "$HOME/.claude/skills"
if [[ -d "$SKILLS_SRC_DIR" ]]; then
    cp -r "$SKILLS_SRC_DIR"/* "$HOME/.claude/skills/"
    echo "Skills copied:"
    ls -la "$HOME/.claude/skills/"
else
    echo "WARNING: skills directory not found: $SKILLS_SRC_DIR"
fi

echo "=== Generate opencode config ==="
mkdir -p "$HOME/.config/opencode"
if [[ -z "${BAILIAN_API_KEY:-}" ]]; then
    echo "ERROR: BAILIAN_API_KEY not set"
    exit 1
fi

cat > "$HOME/.config/opencode/opencode.jsonc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "bailian": {
      "name": "稀宇",
      "npm": "@ai-sdk/anthropic",
      "options": {
        "apiKey": "{env:BAILIAN_API_KEY}",
        "baseURL": "https://api.minimaxi.com/anthropic/v1"
      },
      "models": {
        "MiniMax-M3": {
          "name": "MiniMax-M3"
        }
      }
    }
  }
}
EOF
echo "opencode config generated (apiKey via {env:BAILIAN_API_KEY}, not persisted)"

echo "=== Environment setup complete ==="
