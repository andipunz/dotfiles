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

To test a change, run `./install.sh` and confirm the relevant symlink/tool behaves as expected — there's no automated test suite.

## Structure and symlink mapping

Files here are staged copies; `install.sh` symlinks each into its real location:

| Repo path | Symlinked to |
|---|---|
| `zsh/zshrc` | `~/.zshrc` |
| `git/config` | `~/.config/git/config` |
| `git/ignore` | `~/.config/git/ignore` |
| `ssh/config` | `~/.ssh/config` |

Editing a file in this repo changes the live config after the symlink is (re-)created — but changes only take effect in already-running shells after `source ~/.zshrc` or a new shell.

`Brewfile` is read directly by `brew bundle`, not symlinked.

## Editing conventions

- Keep `zsh-syntax-highlighting` sourced last in `zsh/zshrc` (documented constraint in the file itself — sourcing order matters for it to work correctly).
- `ssh/config` contains real hostnames/IPs for the user's personal servers; treat edits to it as sensitive infrastructure changes, not routine config.
- `git/config` hardcodes the user's name/email — this is intentional (single-user personal machine setup), not a placeholder to templatize.
