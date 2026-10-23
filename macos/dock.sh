#!/usr/bin/env bash
# Apps in the Dock, in this order (Finder and Trash are always there).
#   macos/dock.sh           rebuild the Dock if it differs (install.sh runs this)
#   macos/dock.sh --check   only report a difference, exit 1 if any
set -euo pipefail

APPS=(
  /Applications/Safari.app
  /System/Applications/Mail.app
  /System/Applications/Calendar.app
  /System/Applications/Reminders.app
  /System/Applications/Notes.app
  /System/Applications/Messages.app
  /Applications/Signal.app
  /System/Applications/Photos.app
  /Applications/Ghostty.app
  "/System/Applications/System Settings.app"
)

# Compare by bundle name: the Dock stores Safari under its cryptex path and spaces as %20
want="$(for a in "${APPS[@]}"; do basename "$a"; done)"
have="$(dockutil --list | awk -F'\t' '$3 == "persistentApps" {print $2}' | sed -E 's#/$##; s#.*/##; s#%20# #g')"
[[ $have == "$want" ]] && exit 0

if [[ ${1:-} == --check ]]; then
  echo "  Dock apps differ:"
  diff <(echo "$have") <(echo "$want") | grep '^[<>]' | sed 's/^</  - extra:/; s/^>/  - missing or moved:/'
  exit 1
fi
dockutil --remove all --no-restart >/dev/null
for a in "${APPS[@]}"; do dockutil --add "$a" --no-restart >/dev/null; done
killall Dock
echo "  rebuilt the Dock"
