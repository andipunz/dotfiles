#!/usr/bin/env bash
set -euo pipefail
# launchd starts this with a bare PATH (bash -l finds no profile): add Homebrew for restic
export PATH="/opt/homebrew/bin:$PATH"
STATE="$HOME/Library/Application Support/ResticBackup"
LAST="$STATE/last-snapshot"
# Started hourly by the LaunchAgent; back up at most once a day, quietly skip otherwise:
# - a snapshot from the last 20 hours exists
[[ -f $LAST ]] && (($(date +%s) - $(stat -f %m "$LAST") < 20 * 3600)) && exit 0
# - DarkWake (no Graphics): macOS puts the Mac back to sleep within seconds and the SFTP connection drops
pmset -g systemstate | grep -q Graphics || exit 0
# - offline: the Storage Box isn't reachable (would otherwise notify every hour)
nc -z -G 5 "$(ssh -G storagebox 2>/dev/null | awk '$1 == "hostname" {print $2}')" 23 2>/dev/null || exit 0
# Keep the Mac from idle-sleeping while this script runs
caffeinate -i -w $$ &
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
# Remove locks left by runs that were cut off (only stale ones: dead process or older than 30 minutes)
restic unlock
# Only Documents (synced by iCloud, holds everything important) and Photos: code lives in git,
# everything else isn't worth backing up. Both must be kept fully local (iCloud Drive
# "Keep Downloaded", Photos "Download Originals"), otherwise restic only sees placeholders.
# Exit code 3: snapshot saved, but some files were unreadable; warn, but still prune
rc=0
restic backup "$HOME/Documents" "$HOME/Pictures/Photos Library.photoslibrary" \
  --exclude-file="$EXCLUDES" --one-file-system || rc=$?
if ((rc == 3)); then notify "restic backup incomplete"; elif ((rc != 0)); then notify "restic backup failed"; exit "$rc"; fi
# A job that stops running sends no notification: check.sh and zshrc warn when this gets old
mkdir -p "$STATE" && date '+%F %T' > "$LAST"
restic forget --prune --keep-daily 7 --keep-weekly 4 --keep-monthly 6
# Sundays: verify the repo structure and read back a sample of the data
if [[ $(date +%u) == 7 ]]; then restic check --read-data-subset=5%; fi
