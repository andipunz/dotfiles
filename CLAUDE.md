# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repo for a terminal-first setup (Ghostty, zsh, tmux, AstroNvim). Language toolchains (Go, Python via uv, Node/TypeScript/Vue) run natively from Homebrew; containers are only for services, via Colima. It's a flat set of config files plus one install script — there is no build, lint, or test tooling.

## Setup / apply changes

```bash
./install.sh
```

This is the only "command" in the repo. It's idempotent and:
1. Installs Homebrew if missing (no Oh My Zsh: `zsh/zshrc` is plain zsh).
2. Runs `brew update && brew upgrade && brew bundle --file=Brewfile`.
3. Symlinks dotfiles into place (see mapping below) via a local `link()` helper (`ln -sfn`).
4. `chmod 600`s the SSH config.
5. Loads the restic backup and keyboard remap LaunchAgents.

To test a change, run `./install.sh` and confirm the relevant symlink/tool behaves as expected — there's no automated test suite.

## Structure and symlink mapping

Files here are staged copies; `install.sh` symlinks each into its real location:

| Repo path | Symlinked to |
|---|---|
| `zsh/zshrc` | `~/.zshrc` |
| `ghostty/config` | `~/.config/ghostty/config` |
| `starship/starship.toml` | `~/.config/starship.toml` |
| `nvim/` | `~/.config/nvim` |
| `tmux/tmux.conf` | `~/.config/tmux/tmux.conf` |
| `sesh/sesh.toml` | `~/.config/sesh/sesh.toml` |
| `colima/default.yaml` | `~/.colima/_templates/default.yaml` |
| `git/config` | `~/.config/git/config` |
| `git/config-mbcom` | `~/.config/git/config-mbcom` |
| `git/ignore` | `~/.config/git/ignore` |
| `uv/uv.toml` | `~/.config/uv/uv.toml` |
| `ssh/config` | `~/.ssh/config` |
| `restic/backup.sh` | `~/.config/restic/backup.sh` |
| `restic/excludes.txt` | `~/.config/restic/excludes.txt` |
| `restic/com.andreas.backup.plist` | `~/Library/LaunchAgents/com.andreas.backup.plist` |
| `keyboard/com.andreas.keyboard-remap.plist` | `~/Library/LaunchAgents/com.andreas.keyboard-remap.plist` (swaps Caps Lock and Escape via `hidutil` at login) |

Editing a file in this repo changes the live config after the symlink is (re-)created — but changes only take effect in already-running shells after `source ~/.zshrc` or a new shell.

`Brewfile` is read directly by `brew bundle`, not symlinked. `~/.docker/config.json` is not symlinked either (`docker login` writes to it); `install.sh` merges `cliPluginsExtraDirs` and `credsStore` into it with jq. `~/.npmrc` is likewise not symlinked (`npm login` writes tokens to it); `install.sh` sets `ignore-scripts=true` in it, so dependencies' install scripts don't run (opt in per install with `npm install --ignore-scripts=false`).

## Editing conventions

- Keep `zsh-syntax-highlighting` sourced last in `zsh/zshrc` (documented constraint in the file itself — sourcing order matters for it to work correctly).
- `ssh/config` contains real hostnames/IPs for the user's personal servers; treat edits to it as sensitive infrastructure changes, not routine config.
- `git/config` hardcodes the user's name/email — this is intentional (single-user personal machine setup), not a placeholder to templatize. Repos under `github.com/mbcomdev` or `gitlab.com/mbcomdev` (matched via `includeIf "hasconfig:remote.*.url:..."`, requires git 2.36+) get a different email from `git/config-mbcom` — same name, work address. Credential helpers are split by host (`gh auth git-credential` for github.com, `glab auth git-credential` for gitlab.com) so `git pull`/`push` reuse the tokens those CLIs already manage instead of prompting.
- This repo is **public**. Never commit secrets (restic repository password, SSH private keys, tokens). The restic repo password lives only in the macOS Keychain (`security add-generic-password -a "$USER" -s restic-storagebox -w '<password>'`) and is read at backup time by `restic/backup.sh` — it is never written to a file in this repo.

## Languages and containers

- Toolchains come from the Brewfile, not a version manager: `go` (downloads newer toolchains itself when a `go.mod` asks for one), `uv` (manages Python versions per project; `install.sh` runs `uv python install 3.14 --default` so `~/.local/bin/python3` is a uv-managed Python), and `node@24` (keg-only, added to PATH in `zsh/zshrc`). JS projects use `pnpm` instead of npm (it skips dependency install scripts by default).
- Supply-chain cooldown: uv ignores packages published in the last 7 days (`exclude-newer` in `uv/uv.toml`), and so does pnpm (`minimum-release-age`, set by `install.sh` in its global config).
- `nvim/lua/community.lua` enables AstroCommunity language packs only when the toolchain is on PATH; Mason installs the LSPs natively. Keymaps are AstroNvim defaults (kept identical to the work nixvim config).
- Colima runs Docker without Docker Desktop/OrbStack. It is started on demand (`colima start` / `colima stop`), not at login. `colima/default.yaml` is the template for *new* instances only; changes to it need `colima delete && colima start`. It mounts only `~/git` into the VM (not all of `$HOME`), so bind mounts from elsewhere won't work.

## Restic backup

Backs up only `~/Documents` (synced by iCloud via Desktop & Documents; everything important lives there) and the Photos library (code is backed up by its git remotes, the rest isn't worth keeping) daily at 03:00 to a Hetzner Storage Box (`u693061`, host alias `storagebox` in `ssh/config`, SSH port 23) via restic's SFTP backend. There is no home server; the setup is cloud-only. Restic encrypts client-side, so Hetzner only stores ciphertext. Both must be kept fully local (Finder: Documents → Keep Downloaded; Photos: Download Originals to this Mac), since restic can't read iCloud placeholders. Exit code 3 (snapshot saved, some files unreadable) raises an "incomplete" notification but still prunes. `restic forget --prune` runs after every backup, keeping 7 daily / 4 weekly / 6 monthly snapshots; on Sundays `restic check --read-data-subset=5%` verifies the repo. Failures raise a macOS notification.

Protection against a compromised laptop (which can delete the repo over SFTP) comes from the Storage Box's own automatic snapshots, managed in the Hetzner Console and not reachable via SFTP. Storage Box settings: SSH on, external reachability on, SMB/WebDAV off.

One-time manual setup (not automated by `install.sh`, since these are per-machine secrets/permissions, not config):
1. `ssh-keygen -t ed25519 -f ~/.ssh/storagebox-backup` (with passphrase), `ssh-add --apple-use-keychain ~/.ssh/storagebox-backup`, and add the public key to the Storage Box. `UseKeychain yes` lets the unattended job unlock it.
2. `security add-generic-password -a "$USER" -s restic-storagebox -w '<password>'`: generate and store a strong repo password in Keychain (also keep it in a password manager; without it the backup is unrecoverable).
3. `restic -r sftp:storagebox:restic/macbook-air init`: once, to create the repository.
4. Grant Full Disk Access (System Settings → Privacy & Security) to `~/Applications/ResticBackup.app` so restic can read Documents and the Photos library: required due to TCC, can't be scripted. `install.sh` builds this wrapper once (osacompile, ad-hoc signed) and the LaunchAgent runs it; macOS attributes the restic child process to it. Don't rebuild it (its signature would change and the permission be dropped), and don't grant `/bin/bash` or Homebrew's restic instead: bash would give FDA to every launchd script, and restic's ad-hoc signature changes on each `brew upgrade`.

Check status: `launchctl print gui/$(id -u)/com.andreas.backup`, logs at `~/Library/Logs/restic-backup.log`, snapshots via `restic -r sftp:storagebox:restic/macbook-air snapshots` (with `RESTIC_PASSWORD` sourced from Keychain).
