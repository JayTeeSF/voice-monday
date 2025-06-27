#!/usr/bin/env bash
# setup.sh — idempotent installer for Voice-to-Monday toolkit (macOS)
set -euo pipefail
cd "$(dirname "$0")"

headline() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── Prevent Homebrew auto-update & Git prompts ───────────────────────────────
export HOMEBREW_NO_AUTO_UPDATE=1
export GIT_TERMINAL_PROMPT=0

# ── 1. Xcode CLI tools ───────────────────────────────────────────────────────
if ! xcode-select -p &>/dev/null; then
  headline "Installing Xcode CLI tools…"
  xcode-select --install || true
  while ! xcode-select -p &>/dev/null; do sleep 15; done
fi

# ── 2. rbenv & Ruby from .ruby-version ───────────────────────────────────────
if [[ -f .ruby-version ]]; then
  RUBY_VERSION="$(<.ruby-version)"
  if ! command -v rbenv &>/dev/null; then
    headline "Installing rbenv + ruby-build…"
    brew install rbenv ruby-build
  fi
  export PATH="$(brew --prefix rbenv)/bin:$PATH"
  eval "$(rbenv init -)"
  if ! rbenv versions --bare | grep -qx "$RUBY_VERSION"; then
    headline "Installing Ruby $RUBY_VERSION via rbenv…"
    rbenv install -s "$RUBY_VERSION"
  fi
  rbenv local "$RUBY_VERSION"
else
  if ! ruby -e 'exit Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.3.4")'; then
    headline "Installing Ruby 3.3 via Homebrew…"
    brew install ruby@3.3
    export PATH="$(brew --prefix ruby@3.3)/bin:$PATH"
  fi
fi

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  headline "Installing Homebrew…"
  NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"

# ── 4. Formulae (idempotent) ─────────────────────────────────────────────────
headline "Installing Homebrew formulae…"
for pkg in ffmpeg jq wget unzip; do
  if ! brew list --formula | grep -qx "$pkg"; then
    echo "› brew install $pkg"
    brew install "$pkg"
  fi
done

# ── 5. Gems (idempotent, honors Gemfile) ────────────────────────────────────
headline "Installing Ruby gems…"
gem list -i bundler --no-versions &>/dev/null || gem install bundler --no-document

if [[ -f Gemfile ]]; then
  bundle check || bundle install --jobs 4
else
  for g in ffi tty-command; do
    gem list -i "$g" --no-versions &>/dev/null || gem install "$g" --no-document
  done
fi

# ── 6. Vosk model (≈40 MB) ────────────────────────────────────────────────────
MODEL_DIR="models/vosk-model-small-en-us-0.15"
if [[ ! -d $MODEL_DIR ]]; then
  headline "Fetching Vosk English model…"
  mkdir -p models
  ZIP_URL="https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"
  curl -L "$ZIP_URL" -o models/model.zip
  unzip -q models/model.zip -d models
  rm models/model.zip
fi

# ── 7. Vosk C library (libvosk.dylib) ─────────────────────────────────────────
VOSK_VERSION="0.3.42"
LIB_DIR="lib/vosk"
if [[ ! -f "$LIB_DIR/libvosk.dylib" ]]; then
  headline "Fetching Vosk native library (libvosk.dylib)…"
  mkdir -p "$LIB_DIR"
  ZIP_URL="https://github.com/alphacep/vosk-api/releases/download/v${VOSK_VERSION}/vosk-osx-${VOSK_VERSION}.zip"
  curl -L "$ZIP_URL" -o "$LIB_DIR/vosk-native.zip"
  unzip -q "$LIB_DIR/vosk-native.zip" -d "$LIB_DIR"
  rm "$LIB_DIR/vosk-native.zip"
fi

# ── 8. Export FFI library path ───────────────────────────────────────────────
export VOSK_LIBRARY_PATH="$(pwd)/$LIB_DIR/libvosk.dylib"

headline "✔  Setup complete — run ./voice_task_server.rb to start listening."
