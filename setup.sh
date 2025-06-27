#!/usr/bin/env bash
# setup.sh — idempotent installer for Voice-to-Monday toolkit (macOS)
set -euo pipefail
cd "$(dirname "$0")"

headline() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── Block Brew auto-update / Git prompts ──────────────────────────────────────
export HOMEBREW_NO_AUTO_UPDATE=1
export GIT_TERMINAL_PROMPT=0

# ── 1. Xcode CLI tools ────────────────────────────────────────────────────────
if ! xcode-select -p &>/dev/null; then
  headline "Installing Xcode CLI tools…"
  xcode-select --install || true
  while ! xcode-select -p &>/dev/null; do sleep 15; done
fi

# ── 2. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  headline "Installing Homebrew…"
  NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"

# ── 3. Ruby ≥ 3.3.4 ───────────────────────────────────────────────────────────
if ! ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3.4")'; then
  headline "Installing Ruby 3.3…"
  brew install ruby@3.3
  export PATH="$(brew --prefix ruby@3.3)/bin:$PATH"
fi

# ── 4. Formulae (idempotent) ──────────────────────────────────────────────────
headline "Installing Homebrew formulae…"
for pkg in ffmpeg jq wget unzip; do
  brew list --formula | grep -qx "$pkg" || { echo "› brew install $pkg"; brew install "$pkg"; }
done

# ── 5. Gems (idempotent, no Gemfile needed) ───────────────────────────────────
headline "Installing Ruby gems…"
for gem in bundler vosk tty-command; do
  gem list -i "$gem" --no-versions &>/dev/null || gem install "$gem" --no-document
done

# ── 6. Vosk model (≈ 40 MB) ───────────────────────────────────────────────────
MODEL_DIR="models/vosk-model-small-en-us-0.15"
if [[ ! -d $MODEL_DIR ]]; then
  headline "Fetching Vosk English model…"
  mkdir -p models
  ZIP_URL="https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
  curl -L "$ZIP_URL" -o models/model.zip
  unzip -q models/model.zip -d models
  rm models/model.zip
fi

headline "✔  Setup complete — run ./voice_task_server.rb to start listening."
