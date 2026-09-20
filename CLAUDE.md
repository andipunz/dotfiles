# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repo. It's a flat set of config files plus one install script — there is no build, lint, or test tooling.

## Setup / apply changes

```bash
./install.sh
```

This is the only "command" in the repo. It's idempotent and:
1. Installs Homebrew and Oh My Zsh if missing.
2. Runs `brew update && brew upgrade && brew bundle --file=Brewfile`.
3. Symlinks dotfiles into place (see mapping below) via a local `link()` helper (`ln -sf`).
4. `chmod 600`s the SSH config.
5. Loads the restic backup LaunchAgent.

To test a change, run `./install.sh` and confirm the relevant symlink/tool behaves as expected — there's no automated test suite.

## Structure and symlink mapping

Files here are staged copies; `install.sh` symlinks each into its real location:

| Repo path | Symlinked to |
|---|---|
| `zsh/zshrc` | `~/.zshrc` |
| `git/config` | `~/.config/git/config` |
| `git/config-mbcom` | `~/.config/git/config-mbcom` |
| `git/ignore` | `~/.config/git/ignore` |
| `ssh/config` | `~/.ssh/config` |
| `restic/backup.sh` | `~/.config/restic/backup.sh` |
| `restic/excludes.txt` | `~/.config/restic/excludes.txt` |
| `restic/com.andreas.restic-backup.plist` | `~/Library/LaunchAgents/com.andreas.restic-backup.plist` |

Editing a file in this repo changes the live config after the symlink is (re-)created — but changes only take effect in already-running shells after `source ~/.zshrc` or a new shell.

`Brewfile` is read directly by `brew bundle`, not symlinked.

## Editing conventions

- Keep `zsh-syntax-highlighting` sourced last in `zsh/zshrc` (documented constraint in the file itself — sourcing order matters for it to work correctly).
- `ssh/config` contains real hostnames/IPs for the user's personal servers; treat edits to it as sensitive infrastructure changes, not routine config.
- `git/config` hardcodes the user's name/email — this is intentional (single-user personal machine setup), not a placeholder to templatize. Repos under `github.com/mbcomdev` or `gitlab.com/mbcomdev` (matched via `includeIf "hasconfig:remote.*.url:..."`, requires git 2.36+) get a different email from `git/config-mbcom` — same name, work address. Credential helpers are split by host (`gh auth git-credential` for github.com, `glab auth git-credential` for gitlab.com) so `git pull`/`push` reuse the tokens those CLIs already manage instead of prompting.
- This repo is **public**. Never commit secrets (restic repository password, SSH private keys, tokens). The restic repo password lives only in the macOS Keychain (`security add-generic-password -a "$USER" -s restic-backup-de -w '<password>'`) and is read at backup time by `restic/backup.sh` — it is never written to a file in this repo.

## Restic backup

Backs up `$HOME`, iCloud Drive, and the Photos library to `backup-de` (a ZimaBoard restic server on the owner's home LAN in Germany; server-side provisioning and ACLs live in the separate `infra-punz` repo, since that server is shared with other family members) via restic's SFTP backend, authenticated by **Tailscale SSH** — there is no SSH keypair for this to manage. `restic forget --prune` runs after every backup, keeping 7 daily / 4 weekly / 6 monthly snapshots.

`backup-de` uses a dedicated `backup-andreas` account (Tailscale SSH only, no keys/passwords) that owns its whole directory, so adding another device for the same person needs no `infra-punz` changes — it just gets its own subdirectory under `/backups/usb/andreas/` the first time `restic init` runs against it. Only onboarding a new *person* touches `infra-punz` (see its README).

One-time manual setup (not automated by `install.sh`, since these are per-machine secrets/permissions, not config):
1. `security add-generic-password -a "$USER" -s restic-backup-de -w '<password>'` — generate and store a strong repo password in Keychain.
2. `restic -r sftp:backup-andreas@backup-de:/backups/usb/andreas/macbook-air init` — once, to create the repository.
3. Grant Full Disk Access (System Settings → Privacy & Security) to `restic` so it can read iCloud Drive and the Photos library — required due to TCC, can't be scripted.

Check status: `launchctl list | grep restic-backup`, logs at `~/Library/Logs/restic-backup.log`, snapshots via `restic -r sftp:backup-andreas@backup-de:/backups/usb/andreas/macbook-air snapshots` (with `RESTIC_PASSWORD` sourced from Keychain).
