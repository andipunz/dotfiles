#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

# Homebrew
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$(brew shellenv)"

# Homebrew packages
brew update
brew upgrade
brew bundle --file="$DOTFILES/Brewfile"

# Python: uv-managed CPython as python/python3 in ~/.local/bin (projects pin their own via uv).
# One minor behind the newest release, so third-party wheels are available.
uv python install 3.14 --default --preview-features python-install-default

# Symlinks
link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"  # -n: replace an existing dir symlink (nvim) instead of linking inside it
  echo "  linked $dst"
}

link "$DOTFILES/zsh/zshrc"       "$HOME/.zshrc"
link "$DOTFILES/ghostty/config"  "$HOME/.config/ghostty/config"
link "$DOTFILES/starship/starship.toml" "$HOME/.config/starship.toml"
link "$DOTFILES/nvim"            "$HOME/.config/nvim"
link "$DOTFILES/tmux/tmux.conf"  "$HOME/.config/tmux/tmux.conf"
link "$DOTFILES/colima/default.yaml" "$HOME/.colima/_templates/default.yaml"
link "$DOTFILES/git/config"      "$HOME/.config/git/config"
link "$DOTFILES/git/config-mbcom" "$HOME/.config/git/config-mbcom"
link "$DOTFILES/git/ignore"      "$HOME/.config/git/ignore"
link "$DOTFILES/ssh/config"      "$HOME/.ssh/config"
link "$DOTFILES/restic/backup.sh"     "$HOME/.config/restic/backup.sh"
link "$DOTFILES/restic/excludes.txt"  "$HOME/.config/restic/excludes.txt"
link "$DOTFILES/restic/com.andreas.restic-backup.plist" "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist"
link "$DOTFILES/keyboard/com.andreas.keyboard-remap.plist" "$HOME/Library/LaunchAgents/com.andreas.keyboard-remap.plist"

# Docker CLI (Colima): find Homebrew's compose/buildx plugins, keep registry logins in the Keychain.
# Not symlinked, since `docker login` writes to this file.
DOCKER_CONFIG_FILE="$HOME/.docker/config.json"
mkdir -p "$(dirname "$DOCKER_CONFIG_FILE")"
[[ -f $DOCKER_CONFIG_FILE ]] || echo '{}' > "$DOCKER_CONFIG_FILE"
jq --arg dir "$(brew --prefix)/lib/docker/cli-plugins" \
  '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$dir] | unique) | .credsStore = "osxkeychain"' \
  "$DOCKER_CONFIG_FILE" > "$DOCKER_CONFIG_FILE.tmp" && mv "$DOCKER_CONFIG_FILE.tmp" "$DOCKER_CONFIG_FILE"
echo "  configured $DOCKER_CONFIG_FILE"

# SSH permissions
chmod 600 "$HOME/.ssh/config"
chmod +x "$HOME/.config/restic/backup.sh"

# Restic backup LaunchAgent
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist" 2>/dev/null || \
  launchctl load -w "$HOME/Library/LaunchAgents/com.andreas.restic-backup.plist" 2>/dev/null || true
echo "  loaded restic backup LaunchAgent (daily, 03:00)"

# Caps Lock <-> Escape LaunchAgent (applies now and at every login)
launchctl bootout "gui/$(id -u)/com.andreas.keyboard-remap" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.andreas.keyboard-remap.plist"
echo "  loaded keyboard remap LaunchAgent (Caps Lock <-> Escape)"

echo "Done. Open a new shell or: source ~/.zshrc"
