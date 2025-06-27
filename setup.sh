#!/usr/bin/env bash
# setup.sh — idempotent installer for Voice-to-Monday toolkit (macOS)
set -euo pipefail
cd "$(dirname "$0")"

# ── Avoid Homebrew auto-updates / Git prompts ─────────────────────────────────
export HOMEBREW_NO_AUTO_UPDATE=1
export GIT_TERMINAL_PROMPT=0

# ── Helpers ───────────────────────────────────────────────────────────────────
need()   { command -v "$1" >/dev/null 2>&1; }
headline(){ printf "\n\033[1m%s\033[0m\n" "$*"; }

# ── 1. Xcode CLI tools ─────────────────────────────────────────────────────────
if ! need xcode-select || ! xcode-select -p >/dev/null 2>&1; then
  headline "Installing Xcode CLI…"
  xcode-select --install || true
  while ! xcode-select -p >/dev/null 2>&1; do sleep 15; done
fi

# ── 2. Homebrew itself ─────────────────────────────────────────────────────────
if ! need brew; then
  headline "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

# ── 3. Formulae ─────────────────────────────────────────────────────────────────
headline "Installing Homebrew formulae…"
for pkg in ffmpeg libvosk jq wget unzip; do
  if ! brew list --formula | grep -qx "$pkg"; then
    echo "› brew install $pkg"
    brew install "$pkg"
  fi
done

# ── 4. Ruby & Gems ─────────────────────────────────────────────────────────────
headline "Ensuring Ruby ≥ 3.3.4…"
if ! ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3.4")'; then
  brew install ruby@3.3
  PATH="$(brew --prefix ruby@3.3)/bin:$PATH"
fi

headline "Installing Bundler & gems…"
gem install bundler --no-document
bundle install --quiet

# ── 5. Vosk model ───────────────────────────────────────────────────────────────
MODEL_DIR="models/vosk-model-small-en-us-0.15"
if [ ! -d "$MODEL_DIR" ]; then
  headline "Fetching Vosk English model…"
  mkdir -p models
  URL="https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
  if ! wget -q -O models/model.zip "$URL"; then
    curl -L "$URL" -o models/model.zip
  fi
  unzip -q models/model.zip -d models
  rm models/model.zip
fi

headline "✔  Setup complete — ready to run voice_task_server.rb"
