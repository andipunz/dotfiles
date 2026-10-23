#!/bin/bash
# /bin/bash like macos/system.sh: under Homebrew's bash, netstat returns nothing on macOS 27
# Read-only drift check: does this Mac match the repo? Changes nothing.
# Fix drift with ./install.sh, or adopt it by editing the repo (Brewfile, macos/defaults.sh).
set -uo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1
drift=0
section() { echo; echo "== $1"; }

section "Repo"
git -C "$DOTFILES" fetch --quiet 2>/dev/null || echo "  (fetch failed, comparing with last known remote)"
if [[ -n $(git -C "$DOTFILES" status --porcelain) ]]; then echo "  uncommitted changes"; drift=1; fi
behind="$(git -C "$DOTFILES" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
ahead="$(git -C "$DOTFILES" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
((behind > 0)) && { echo "  $behind commit(s) to pull"; drift=1; }
((ahead > 0)) && { echo "  $ahead commit(s) to push"; drift=1; }

section "Homebrew: missing from this Mac"
brew bundle check --file="$DOTFILES/Brewfile" --verbose --no-upgrade | grep -v "satisfied" || true
brew bundle check --file="$DOTFILES/Brewfile" --no-upgrade >/dev/null || drift=1

section "Homebrew: installed but not in the Brewfile"
# Only the uninstall/untap part of the dry run; cache cleanup ("Would `brew cleanup`") isn't drift
extra="$(brew bundle cleanup --file="$DOTFILES/Brewfile" 2>/dev/null | awk '/^Would .brew cleanup.|^Run /{exit} {print "  " $0}')"
if [[ -n $extra ]]; then echo "$extra"; drift=1; fi

section "Symlinks"
# Every `link src dst` line in install.sh must point into the repo
while read -r src dst; do
  src="${src//\$DOTFILES/$DOTFILES}"; dst="${dst//\$HOME/$HOME}"
  [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] || { echo "  $dst does not link to $src"; drift=1; }
done < <(grep -E '^link "' "$DOTFILES/install.sh" | sed -E 's/^link +"([^"]+)" +"([^"]+)".*/\1 \2/')

section "LaunchAgents"
for plist in "$HOME"/Library/LaunchAgents/*.plist; do
  label="$(basename "$plist" .plist)"
  launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || { echo "  $label not loaded"; drift=1; }
  [[ -L $plist ]] || { echo "  $label is not from the repo"; drift=1; }
done
for d in /Library/LaunchAgents /Library/LaunchDaemons; do
  for plist in "$d"/*.plist; do [[ -e $plist ]] && { echo "  system-wide: $plist"; drift=1; }; done
done

section "gh extensions"
exts="$(gh extension list)"
for ext in dlvhdr/gh-dash dlvhdr/gh-enhance; do
  [[ $exts == *"$ext"* ]] || { echo "  $ext not installed"; drift=1; }
done

section "Local files (personal, not in the repo)"
for f in "$HOME/.ssh/config.local" "$HOME/.config/git/config-mbcom"; do
  [[ -f $f && ! -L $f ]] || { echo "  $f missing"; drift=1; }
done
[[ $(go env GOPRIVATE) == *mbcomdev* ]] || { echo "  GOPRIVATE not set (install.sh)"; drift=1; }

section "Backup"
last="$HOME/Library/Application Support/ResticBackup/last-snapshot"
if [[ ! -f $last ]]; then echo "  no snapshot recorded yet (restic/backup.sh)"; drift=1
elif (( $(date +%s) - $(stat -f %m "$last") > 3 * 86400 )); then echo "  last snapshot $(cat "$last")"; drift=1; fi

section "macOS settings"
"$DOTFILES/macos/defaults.sh" --check || drift=1
"$DOTFILES/macos/dock.sh" --check || drift=1

section "System and security"
"$DOTFILES/macos/system.sh" --check || drift=1

echo
if ((drift)); then echo "Drift found."; else echo "This Mac matches the repo."; fi
exit "$drift"
