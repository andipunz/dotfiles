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
2. Runs `brew update && brew upgrade && brew bundle --file=Brewfile`, then `brew bundle cleanup --force`: anything installed but not in the Brewfile is uninstalled.
3. Symlinks dotfiles into place (see mapping below) via a local `link()` helper (`ln -sfn`).
4. `chmod 600`s the SSH config.
5. Builds the document filing OCR helper and wrapper app (see "Document filing").
6. Loads the document filing, restic backup and keyboard remap LaunchAgents.
7. Installs the gh extensions (gh-dash, gh-enhance) and applies `macos/defaults.sh` (user settings), `macos/dock.sh` (Dock apps) and `macos/system.sh` (system-wide settings and security baseline; re-runs itself with sudo).

`./check.sh` is the read-only counterpart: it reports drift between the Mac and the repo (uncommitted/unpulled commits, missing or extra Homebrew packages, broken symlinks, LaunchAgents not loaded or not from the repo, system-wide LaunchAgents/Daemons, macOS settings, backup age, FileVault and firewall) and changes nothing. Run it before `./install.sh` to see what the cleanup would uninstall.

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
| `git/ignore` | `~/.config/git/ignore` |
| `uv/uv.toml` | `~/.config/uv/uv.toml` |
| `atuin/config.toml` | `~/.config/atuin/config.toml` (only the non-default keys) |
| `gh/config.yml` | `~/.config/gh/config.yml` (no tokens: gh keeps them in the Keychain, `hosts.yml` stays local) |
| `gh-dash/config.yml` | `~/.config/gh-dash/config.yml` |
| `claude/settings.json` | `~/.claude/settings.json` (Claude Code user settings, no telemetry, error reports or update checks, no reading of `~/.ssh`, `.env` files or `~/Documents/.ablage.json`) |
| `ssh/config` | `~/.ssh/config` (only the `Host *` defaults; the hosts are in `~/.ssh/config.local`, see below) |
| `restic/backup.sh` | `~/.config/restic/backup.sh` |
| `restic/excludes.txt` | `~/.config/restic/excludes.txt` |
| `restic/com.andreas.backup.plist` | `~/Library/LaunchAgents/com.andreas.backup.plist` |
| `keyboard/com.andreas.keyboard-remap.plist` | `~/Library/LaunchAgents/com.andreas.keyboard-remap.plist` (swaps Caps Lock and Escape via `hidutil` at login) |
| `ablage/ablage.py`, `ablage/aufbewahrung.py`, `ablage/postfach.py`, `ablage/luecken.py` | `~/.config/ablage/` |
| `ablage/com.andreas.ablage.plist`, `ablage/com.andreas.aufbewahrung.plist` | `~/Library/LaunchAgents/` |

Editing a file in this repo changes the live config after the symlink is (re-)created — but changes only take effect in already-running shells after `source ~/.zshrc` or a new shell.

`Brewfile` is read directly by `brew bundle`, not symlinked. `~/.docker/config.json` is not symlinked either (`docker login` writes to it); `install.sh` merges `cliPluginsExtraDirs` and `credsStore` into it with jq. `~/.npmrc` is likewise not symlinked (`npm login` writes tokens to it); `install.sh` sets `ignore-scripts=true` in it, so dependencies' install scripts don't run (opt in per install with `npm install --ignore-scripts=false`).

## Editing conventions

- Keep `zsh-syntax-highlighting` sourced last in `zsh/zshrc` (documented constraint in the file itself — sourcing order matters for it to work correctly).
- Personal details stay out of this public repo. Two local files, not symlinked, hold them: `~/.ssh/config.local` (every `Host` block: server names, addresses, users, keys, the Storage Box account), included at the top of `ssh/config`, and `~/.config/git/config-mbcom` (the work email). On a new Mac copy both from the old one (or a password manager); `check.sh` reports them if missing. Claude Code can't read `~/.ssh`, so edits to `config.local` are done by hand. SSH connections are shared per host for 10 minutes (`ControlMaster`, sockets `~/.ssh/cm-*`), except `storagebox`: a persisting master would keep restic's stderr open and hang the backup.
- `.github/workflows/lint.yml` runs shellcheck (`--severity=warning`) and gitleaks on every push; actions are pinned to commit SHAs.
- `git/config` hardcodes the user's name and GitHub's no-reply email (`75120851+andipunz@users.noreply.github.com`) as the default, so no commit shows the real address — this is intentional (single-user personal machine setup), not a placeholder to templatize. Repos under `github.com/mbcomdev` or `gitlab.com/mbcomdev` (matched via `includeIf "hasconfig:remote.*.url:..."`, requires git 2.36+) get the work email from the local `~/.config/git/config-mbcom` — same name. `install.sh` sets `GOPRIVATE` for the same two paths, so Go fetches work modules directly and their paths never reach proxy.golang.org or sum.golang.org. Credential helpers are split by host (`gh auth git-credential` for github.com, `glab auth git-credential` for gitlab.com) so `git pull`/`push` reuse the tokens those CLIs already manage instead of prompting.
- `gitleaks` scans staged changes before every commit in every repo, via a config-based hook (`hook.gitleaks` in `git/config`, git 2.54+), so repos' own `.git/hooks` keep running. Skip once with `git commit --no-verify`.
- This repo is **public**. Never commit secrets (restic repository password, SSH private keys, tokens). The restic repo password lives only in the macOS Keychain (`security add-generic-password -a "$USER" -s restic-storagebox -w '<password>'`) and is read at backup time by `restic/backup.sh` — it is never written to a file in this repo.

## Languages and containers

- Toolchains come from the Brewfile, not a version manager: `go` (downloads newer toolchains itself when a `go.mod` asks for one), `uv` (manages Python versions per project; `install.sh` runs `uv python install 3.14 --default` so `~/.local/bin/python3` is a uv-managed Python), and `node@24` (keg-only, added to PATH in `zsh/zshrc`). JS projects use `pnpm` instead of npm (it skips dependency install scripts by default).
- Supply-chain cooldown: uv ignores packages published in the last 7 days (`exclude-newer` in `uv/uv.toml`), and so does pnpm (`minimum-release-age`, set by `install.sh` in its global config).
- `nvim/lua/community.lua` enables AstroCommunity language packs only when the toolchain is on PATH; Mason installs the LSPs natively. Keymaps are AstroNvim defaults (kept identical to the work nixvim config).
- Colima runs Docker without Docker Desktop/OrbStack. It is started on demand (`colima start` / `colima stop`), not at login. `colima/default.yaml` is the template for *new* instances only; changes to it need `colima delete && colima start`. It mounts only `~/git` into the VM (not all of `$HOME`), so bind mounts from elsewhere won't work.

## macOS settings

The goal is no clickops. Three scripts, each with an apply mode (run by `install.sh`) and a read-only `--check` mode (run by `check.sh`):

- `macos/defaults.sh`: user settings as `pref <domain> <key> <type> <value>` lines (`hpref` for per-machine ByHost keys), only what differs from a fresh macOS. Restarts Dock/Finder/Control Center when their settings changed; keyboard settings need a logout. To add a setting, diff `defaults read` (and `defaults -currentHost read`) before and after changing it in System Settings.
- `macos/dock.sh`: the Dock's apps in order (`APPS`), rebuilt with `dockutil` only when they differ.
- `macos/system.sh`: root settings and the security baseline as `item <description> <test> [<fix>]`: FileVault, SIP, Gatekeeper, firewall and stealth mode, Touch ID for sudo via `/etc/pam.d/sudo_local` (with `pam_reattach` for tmux), lock screen, guest/auto-login, sharing services and AirPlay Receiver off (checked via listening ports), automatic updates, no analytics, display sleep, host names (`mba`). Items without a fix are reported as "by hand". It runs under `/bin/bash`: under Homebrew's ad-hoc signed bash, `netstat` returns nothing on macOS 27.

Not codifiable without MDM, so done by hand on a new Mac: Apple ID/iCloud and App Store sign-in, Apple Intelligence, turning on FileVault, screen lock delay and AirPlay Receiver (both checked), privacy permissions like Full Disk Access, notifications, Focus, location services, Safari, AdGuard and Signal settings. Text replacements sync via iCloud. If another device on the network is called `mba`, macOS renames the LocalHostName to `mba-2` and `check.sh` reports it.

## Document filing (ablage)

Files dropped into `~/Documents/_Eingang` are renamed and filed automatically. `ablage/ablage.py` (plain `/usr/bin/python3`, stdlib only, so it doesn't depend on uv) reads the text (PDF text, Vision OCR for scans and photos via `~/.config/ablage/extract`, built by `install.sh` from `ablage/extract.swift`), moves exact duplicates to `_Papierkorb`, applies fixed rules (DKB statements, payslips, Lohnsteuerbescheinigungen, DRV Renteninformation, plus sender rules from the config) and asks `claude -p` (no tools, JSON schema output) for everything else. Results are validated against the naming scheme before moving; anything below 75 % confidence, off-scheme, or failing goes to `_Pruefen`. Nothing is overwritten or deleted. `aufbewahrung.py` writes a yearly retention report (2 January) to `_Pruefen`; it never deletes.

Naming scheme (enforced by regex in `ablage.py`): folders `NN_Bereich` at the top, `Wort-Wort` below, years `YYYY`; files `YYYY-MM-DD_Typ_Absender_Detail.ext`, no spaces, umlauts, or special characters.

- Personal data stays out of this public repo: owner, employer names (for the payslip rule), sender rules with contract numbers (`rules`), expected document series (`expect`), the IMAP login (`imap`), `use_claude` and `model` are read from `~/Documents/.ablage.json`, which iCloud syncs to every Mac. Without it the scripts still run, with no employer/sender rules, no mail and a generic prompt. The format of each key is documented in the docstrings of `ablage.py`, `postfach.py` and `luecken.py`.
- Letter dates come from `letter_date()`: the date before the salutation, else the first header date, checked against the Deutsche Post posting mark (`DV MM.YY`) so effective dates and periods in the body aren't picked. Test changes to rules against real letters before committing.
- Mail: archive a mail on any device (iCloud's `Archive` folder). Each run (at most every 5 minutes) `postfach.py` puts its attachments (PDF, images ≥ 30 KB, Office files) into `_Eingang`, saves the whole mail as `~/Documents/10_Mail-Archiv/YYYY/YYYY-MM-DD_Mail_Absender_Betreff.eml` (end-to-end encrypted via Advanced Data Protection and in the restic backup; iCloud Mail is not) and moves it to `Archive/Erledigt` (or `Archive/Ohne-Anhang`). Sender, subject and date are passed to Claude. Once a day it deletes mails from those two subfolders that were filed more than 30 days ago, only if their `.eml` is present with the recorded size (`mail-archive.json` in Application Support). The old `Ablage` folders are still emptied into the `Archive` ones. `aufbewahrung.py` lists archived mails after 10 years.
- Gaps: once a week `luecken.py` checks the `expect` series and writes `_Pruefen/YYYY-MM-DD_Bericht_Fehlende-Dokumente.md` (replacing the previous one) plus a notification. Run by hand: `/usr/bin/python3 ~/.config/ablage/luecken.py`.
- `com.andreas.ablage` runs on changes to `_Eingang` (`WatchPaths`) and every 10 minutes; `com.andreas.aufbewahrung` yearly. Both start `~/Applications/Dokumentenablage.app` (osacompile wrapper, same reasoning as ResticBackup.app below), which picks the script from the `ABLAGE_JOB` environment variable.
- Undo log: `~/Library/Application Support/Dokumentenablage/ablage-log.csv`; `python3 ~/.config/ablage/ablage.py --undo` puts the last filed document back into `_Eingang`. Job output: `~/Library/Logs/ablage.log`.

One-time manual setup on a new Mac: grant Full Disk Access to `~/Applications/Dokumentenablage.app` (don't rebuild it afterwards, the permission is tied to its signature), log in to Claude Code once (`claude`) so the headless calls are authenticated, and store the iCloud app-specific password for mail in the Keychain: `security add-generic-password -a <name>@icloud.com -s ablage-imap -w` (created at appleid.apple.com; the IMAP user is the @icloud.com address, not a custom-domain alias).

## Restic backup

Backs up only `~/Documents` (synced by iCloud via Desktop & Documents; everything important lives there) and the Photos library (code is backed up by its git remotes, the rest isn't worth keeping) once a day to a Hetzner Storage Box (host alias `storagebox` in `~/.ssh/config.local`, SSH port 23) via restic's SFTP backend. There is no home server; the setup is cloud-only. Restic encrypts client-side, so Hetzner only stores ciphertext. Both must be kept fully local (Finder: Documents → Keep Downloaded; Photos: Download Originals to this Mac), since restic can't read iCloud placeholders. The LaunchAgent starts `backup.sh` hourly and at login; it skips quietly unless the last snapshot is over 20 hours old, the Mac is fully awake (`pmset -g systemstate` lists Graphics: a scheduled 03:00 run landed in a DarkWake, which macOS ends within seconds on battery, so the SFTP connection dropped) and the Storage Box is reachable. It keeps the Mac awake with `caffeinate` and starts with `restic unlock` to clear stale locks from cut-off runs. Exit code 3 (snapshot saved, some files unreadable) raises an "incomplete" notification but still prunes. Each snapshot writes its time to `~/Library/Application Support/ResticBackup/last-snapshot`; new shells and `check.sh` warn when it is older than 3 days, since a job that stops running (lost Full Disk Access, unloaded agent) raises no notification. `restic forget --prune` runs after every backup, keeping 7 daily / 4 weekly / 6 monthly snapshots; on Sundays `restic check --read-data-subset=5%` verifies the repo. Failures raise a macOS notification.

Protection against a compromised laptop (which can delete the repo over SFTP) comes from the Storage Box's own automatic snapshots, managed in the Hetzner Console and not reachable via SFTP. Storage Box settings: SSH on, external reachability on, SMB/WebDAV off.

One-time manual setup (not automated by `install.sh`, since these are per-machine secrets/permissions, not config):
1. `ssh-keygen -t ed25519 -f ~/.ssh/storagebox-backup` (with passphrase), `ssh-add --apple-use-keychain ~/.ssh/storagebox-backup`, and add the public key to the Storage Box. `UseKeychain yes` lets the unattended job unlock it.
2. `security add-generic-password -a "$USER" -s restic-storagebox -w '<password>'`: generate and store a strong repo password in Keychain (also keep it in a password manager; without it the backup is unrecoverable).
3. `restic -r sftp:storagebox:restic/macbook-air init`: once, to create the repository.
4. Grant Full Disk Access (System Settings → Privacy & Security) to `~/Applications/ResticBackup.app` so restic can read Documents and the Photos library: required due to TCC, can't be scripted. `install.sh` builds this wrapper once (osacompile, ad-hoc signed) and the LaunchAgent runs it; macOS attributes the restic child process to it. Don't rebuild it (its signature would change and the permission be dropped), and don't grant `/bin/bash` or Homebrew's restic instead: bash would give FDA to every launchd script, and restic's ad-hoc signature changes on each `brew upgrade`.

Check status: `launchctl print gui/$(id -u)/com.andreas.backup`, logs at `~/Library/Logs/restic-backup.log`, snapshots via `restic -r sftp:storagebox:restic/macbook-air snapshots` (with `RESTIC_PASSWORD` sourced from Keychain).
