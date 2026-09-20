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
brew update
brew upgrade
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
link "$DOTFILES/git/config-mbcom" "$HOME/.config/git/config-mbcom"
link "$DOTFILES/git/ignore"      "$HOME/.config/git/ignore"
link "$DOTFILES/ssh/config"      "$HOME/.ssh/config"
link "$DOTFILES/restic/backup.sh"     "$HOME/.config/restic/backup.sh"
link "$DOTFILES/restic/excludes.txt"  "$HOME/.config/restic/excludes.txt"
link "$DOTFILES/restic/com.andreas.restic-backup.plist" "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist"
link "$DOTFILES/aerospace/aerospace.toml" "$HOME/.aerospace.toml"

# SSH permissions
chmod 600 "$HOME/.ssh/config"
chmod +x "$HOME/.config/restic/backup.sh"

# Restic backup LaunchAgent
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist" 2>/dev/null || \
  launchctl load -w "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist" 2>/dev/null || true
echo "  loaded restic backup LaunchAgent (daily, 03:00)"

echo "Done. Open a new shell or: source ~/.zshrc"
