#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(brew shellenv)"

# Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Homebrew packages
brew bundle --file="$DOTFILES/Brewfile"

# Symlinks
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sf "$src" "$dst"
  echo "  linked $dst"
}

link "$DOTFILES/zsh/zshrc"       "$HOME/.zshrc"
link "$DOTFILES/git/config"      "$HOME/.config/git/config"
link "$DOTFILES/git/ignore"      "$HOME/.config/git/ignore"
link "$DOTFILES/ssh/config"      "$HOME/.ssh/config"

# SSH permissions
chmod 600 "$HOME/.ssh/config"

echo "Done. Open a new shell or: source ~/.zshrc"
