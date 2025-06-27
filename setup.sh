#!/usr/bin/env bash
# setup.sh — idempotent installer for Voice-to-Monday toolkit
set -euo pipefail

# ────────── helpers ──────────
need()   { command -v "$1" >/dev/null 2>&1; }
have_ruby() { ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3.4")' 2>/dev/null; }
headline() { printf "\n\033[1m%s\033[0m\n" "$*"; }

# ────────── Xcode CLI tools ──────────
if ! need xcode-select || ! xcode-select -p >/dev/null 2>&1; then
  headline "Installing Xcode Command-Line Tools…"
  xcode-select --install || true
  # Wait until installation finishes (macOS shows a dialog)
  while ! xcode-select -p >/dev/null 2>&1; do sleep 20; done
fi

# ────────── Homebrew ──────────
if ! need brew; then
  headline "Installing Homebrew…"
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew in PATH (both arm64 & x86_64)
if [[ "$(uname -m)" == "arm64" ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  eval "$(/usr/local/bin/brew shellenv)"
fi

headline "Updating Homebrew…"
brew update --quiet

# ────────── Ruby 3.3.4 ──────────
if ! have_ruby; then
  headline "Installing Ruby 3.3.4…"
  brew install ruby@3.3
  RUBY_FORMULA_PATH="$(brew --prefix ruby@3.3)/bin"
  [[ ":$PATH:" != *":$RUBY_FORMULA_PATH:"* ]] && echo "export PATH=\"$RUBY_FORMULA_PATH:\$PATH\"" >> ~/.zshrc
  export PATH="$RUBY_FORMULA_PATH:$PATH"
fi

# ────────── Core packages ──────────
headline "Installing formulae…"
brew bundle --file=- <<'BREW'
brew "ffmpeg"          # microphone capture
brew "libvosk"         # speech recognition runtime
brew "jq"
brew "wget"
brew "unzip"
BREW

# ────────── Ruby gems ──────────
headline "Installing gems…"
gem install bundler --no-document
bundle install --quiet

# ────────── Download Vosk model ──────────
MODEL_DIR="models/vosk-model-small-en-us-0.15"
ZIP_URL="https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"

if [ ! -d "$MODEL_DIR" ]; then
  headline "Fetching Vosk English model…"
  mkdir -p models
  wget -q -O models/model.zip "$ZIP_URL" || curl -L "$ZIP_URL" -o models/model.zip
  unzip -q models/model.zip -d models
  rm models/model.zip
fi

headline "✔  Setup complete."

