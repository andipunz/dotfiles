#!/usr/bin/env bash
set -euo pipefail

RESTIC_REPOSITORY="sftp:backup-andreas@backup-de:/backups/usb/andreas/macbook-air"
RESTIC_PASSWORD="$(security find-generic-password -a "$USER" -s restic-backup-de -w)"
export RESTIC_REPOSITORY RESTIC_PASSWORD

EXCLUDES="$HOME/.config/restic/excludes.txt"

restic backup \
  "$HOME" \
  "$HOME/Library/Mobile Documents/com~apple~CloudDocs" \
  "$HOME/Pictures/Photos Library.photoslibrary" \
  --exclude-file="$EXCLUDES" \
  --one-file-system

restic forget --prune \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6
