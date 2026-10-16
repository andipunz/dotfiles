#!/usr/bin/env bash
set -euo pipefail
# launchd starts this with a bare PATH (bash -l finds no profile): add Homebrew for restic
export PATH="/opt/homebrew/bin:$PATH"
# Failures would otherwise only show up in ~/Library/Logs/restic-backup.log
notify() { osascript -e "display notification \"See ~/Library/Logs/restic-backup.log\" with title \"$1\""; }
trap 'notify "restic backup failed"' ERR
# Hetzner Storage Box (host alias in ssh/config); its automatic snapshots protect the repo
# against deletion from this machine
RESTIC_REPOSITORY="sftp:storagebox:restic/macbook-air"
RESTIC_PASSWORD="$(security find-generic-password -a "$USER" -s restic-storagebox -w)"
export RESTIC_REPOSITORY RESTIC_PASSWORD
EXCLUDES="$HOME/.config/restic/excludes.txt"
echo "=== $(date '+%F %T') backup"
# Only iCloud Drive and Photos: code lives in git, everything else isn't worth backing up.
# Both must be kept fully local (iCloud Drive "Keep Downloaded", Photos "Download Originals"),
# otherwise restic only sees placeholders.
# Exit code 3: snapshot saved, but some files were unreadable; warn, but still prune
rc=0
restic backup "$HOME/Library/Mobile Documents/com~apple~CloudDocs" "$HOME/Pictures/Photos Library.photoslibrary" \
  --exclude-file="$EXCLUDES" --one-file-system || rc=$?
if ((rc == 3)); then notify "restic backup incomplete"; elif ((rc != 0)); then notify "restic backup failed"; exit "$rc"; fi
restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
# Sundays: verify the repo structure and read back a sample of the data
if [[ $(date +%u) == 7 ]]; then restic check --read-data-subset=5%; fi
