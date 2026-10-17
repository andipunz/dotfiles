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
link "$DOTFILES/sesh/sesh.toml"  "$HOME/.config/sesh/sesh.toml"
link "$DOTFILES/colima/default.yaml" "$HOME/.colima/_templates/default.yaml"
link "$DOTFILES/git/config"      "$HOME/.config/git/config"
link "$DOTFILES/git/config-mbcom" "$HOME/.config/git/config-mbcom"
link "$DOTFILES/git/ignore"      "$HOME/.config/git/ignore"
link "$DOTFILES/uv/uv.toml"      "$HOME/.config/uv/uv.toml"
link "$DOTFILES/ssh/config"      "$HOME/.ssh/config"
link "$DOTFILES/restic/backup.sh"     "$HOME/.config/restic/backup.sh"
link "$DOTFILES/restic/excludes.txt"  "$HOME/.config/restic/excludes.txt"
link "$DOTFILES/restic/com.andreas.backup.plist" "$HOME/Library/LaunchAgents/com.andreas.backup.plist"
link "$DOTFILES/keyboard/com.andreas.keyboard-remap.plist" "$HOME/Library/LaunchAgents/com.andreas.keyboard-remap.plist"
link "$DOTFILES/ablage/ablage.py"       "$HOME/.config/ablage/ablage.py"
link "$DOTFILES/ablage/aufbewahrung.py" "$HOME/.config/ablage/aufbewahrung.py"
link "$DOTFILES/ablage/com.andreas.ablage.plist"       "$HOME/Library/LaunchAgents/com.andreas.ablage.plist"
link "$DOTFILES/ablage/com.andreas.aufbewahrung.plist" "$HOME/Library/LaunchAgents/com.andreas.aufbewahrung.plist"

# Docker CLI (Colima): find Homebrew's compose/buildx plugins, keep registry logins in the Keychain.
# Not symlinked, since `docker login` writes to this file.
DOCKER_CONFIG_FILE="$HOME/.docker/config.json"
mkdir -p "$(dirname "$DOCKER_CONFIG_FILE")"
[[ -f $DOCKER_CONFIG_FILE ]] || echo '{}' > "$DOCKER_CONFIG_FILE"
jq --arg dir "$(brew --prefix)/lib/docker/cli-plugins" \
  '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$dir] | unique) | .credsStore = "osxkeychain"' \
  "$DOCKER_CONFIG_FILE" > "$DOCKER_CONFIG_FILE.tmp" && mv "$DOCKER_CONFIG_FILE.tmp" "$DOCKER_CONFIG_FILE"
echo "  configured $DOCKER_CONFIG_FILE"

# npm: no install scripts from dependencies (the usual supply-chain attack path). Not symlinked,
# since `npm login` writes tokens to ~/.npmrc. Per install: npm install --ignore-scripts=false
PATH="$(brew --prefix)/opt/node@24/bin:$PATH" npm config set ignore-scripts true
echo "  configured ~/.npmrc (ignore-scripts)"

# pnpm (used instead of npm): skips dependency install scripts by default; also ignore package
# versions younger than a week (in minutes), like exclude-newer in uv/uv.toml
pnpm config set minimum-release-age 10080 --global
echo "  configured pnpm (minimum-release-age)"

# No usage data from CLIs that collect it by default
glab config set telemetry false --global
go telemetry off
echo "  disabled glab and Go telemetry"

# SSH permissions
chmod 600 "$HOME/.ssh/config"
chmod +x "$HOME/.config/restic/backup.sh"

# Restic backup app: the LaunchAgent starts this wrapper, so Full Disk Access is granted to it alone
# (not to /bin/bash, or to Homebrew's ad-hoc signed restic, which loses the permission on every upgrade).
# Built only once: rebuilding changes its signature and macOS would drop the permission.
RESTIC_APP="$HOME/Applications/ResticBackup.app"
if [[ ! -d $RESTIC_APP ]]; then
  mkdir -p "$HOME/Applications"
  osacompile -o "$RESTIC_APP" \
    -e 'try' \
    -e 'do shell script "$HOME/.config/restic/backup.sh >> $HOME/Library/Logs/restic-backup.log 2>&1"' \
    -e 'end try'
  plutil -replace LSUIElement -bool true "$RESTIC_APP/Contents/Info.plist"  # no Dock icon
  codesign --force --sign - "$RESTIC_APP"
  echo "  built $RESTIC_APP: grant it Full Disk Access in System Settings"
fi

# Document filing (ablage/): OCR helper, rebuilt when its source changes (it runs as a child of the
# wrapper app, so rebuilding it doesn't affect any permission)
ABLAGE_EXTRACT="$HOME/.config/ablage/extract"
if [[ ! -x $ABLAGE_EXTRACT || $DOTFILES/ablage/extract.swift -nt $ABLAGE_EXTRACT ]]; then
  swiftc -O "$DOTFILES/ablage/extract.swift" -o "$ABLAGE_EXTRACT"
  echo "  built $ABLAGE_EXTRACT"
fi
mkdir -p "$HOME/Documents/_Eingang"

# Document filing app: like ResticBackup.app, holds Full Disk Access for ~/Documents. The LaunchAgent
# sets ABLAGE_JOB (ablage or aufbewahrung) to pick the script. Built only once (see restic below).
ABLAGE_APP="$HOME/Applications/Dokumentenablage.app"
if [[ ! -d $ABLAGE_APP ]]; then
  mkdir -p "$HOME/Applications"
  osacompile -o "$ABLAGE_APP" \
    -e 'set job to system attribute "ABLAGE_JOB"' \
    -e 'if job is not in {"ablage", "aufbewahrung"} then set job to "ablage"' \
    -e 'try' \
    -e 'do shell script "/usr/bin/python3 $HOME/.config/ablage/" & job & ".py >> $HOME/Library/Logs/ablage.log 2>&1"' \
    -e 'end try'
  plutil -replace LSUIElement -bool true "$ABLAGE_APP/Contents/Info.plist"  # no Dock icon
  codesign --force --sign - "$ABLAGE_APP"
  echo "  built $ABLAGE_APP: grant it Full Disk Access in System Settings"
fi

# Document filing LaunchAgents (inbox watcher, yearly retention report)
for agent in com.andreas.ablage com.andreas.aufbewahrung; do
  launchctl bootout "gui/$(id -u)/$agent" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$agent.plist"
done
echo "  loaded document filing LaunchAgents (~/Documents/_Eingang, retention report on 2 January)"

# Restic backup LaunchAgent
launchctl bootout "gui/$(id -u)/com.andreas.backup" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.andreas.backup.plist"
echo "  loaded restic backup LaunchAgent (daily, 03:00)"

# Caps Lock <-> Escape LaunchAgent (applies now and at every login)
launchctl bootout "gui/$(id -u)/com.andreas.keyboard-remap" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.andreas.keyboard-remap.plist"
echo "  loaded keyboard remap LaunchAgent (Caps Lock <-> Escape)"

echo "Done. Open a new shell or: source ~/.zshrc"
