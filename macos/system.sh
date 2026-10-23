#!/bin/bash
# shellcheck disable=SC2034  # variables are used in the eval'd tests and fixes
# /bin/bash, not Homebrew's: under the ad-hoc signed Homebrew bash, netstat returns nothing on macOS 27
# System-wide settings and security baseline (root).
#   macos/system.sh           apply (install.sh runs this; re-runs itself with sudo)
#   macos/system.sh --check   only report what differs, exit 1 if any (no sudo needed)
# Each item is a test and, where macOS allows it, a fix; the rest is reported as "by hand".
set -euo pipefail

mode="${1:-apply}"
if [[ $mode != --check && $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

NAME=mba
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
SU=/Library/Preferences/com.apple.SoftwareUpdate
LW=/Library/Preferences/com.apple.loginwindow
CR="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
# Touch ID for sudo; pam_reattach makes it work inside tmux (Brewfile: pam-reattach).
# sudo_local survives macOS updates, unlike edits to /etc/pam.d/sudo.
SUDO_LOCAL="auth       optional       /opt/homebrew/lib/pam/pam_reattach.so ignore_ssh
auth       sufficient     pam_tid.so"
# Listening TCP ports, read once (grep -q in a pipe would trip pipefail)
LISTEN="$(netstat -an -p tcp | grep LISTEN || true)"
drift=0

# item <description> <test> [<fix>]
item() {
  local desc="$1" test="$2" fix="${3:-}"
  eval "$test" >/dev/null 2>&1 && return
  if [[ $mode == --check ]]; then
    echo "  $desc"
    drift=1
  elif [[ -z $fix ]]; then
    echo "  by hand: $desc"
    drift=1
  else
    eval "$fix" >/dev/null && echo "  fixed: $desc"
  fi
}

# Security
item "FileVault on (System Settings > Privacy & Security)" 'fdesetup status | grep -q "is On"'
item "System Integrity Protection on (recovery mode: csrutil enable)" 'csrutil status | grep -q enabled'
item "Gatekeeper on" 'spctl --status | grep -q "assessments enabled"' 'spctl --global-enable'
item "Firewall on" '$FW --getglobalstate | grep -q enabled' '$FW --setglobalstate on'
item "Firewall stealth mode on" '$FW --getstealthmode | grep -q " on"' '$FW --setstealthmode on'
item "Touch ID for sudo (/etc/pam.d/sudo_local)" '[[ $(cat /etc/pam.d/sudo_local) == "$SUDO_LOCAL" ]]' \
  'printf "%s\n" "$SUDO_LOCAL" > /etc/pam.d/sudo_local && chmod 444 /etc/pam.d/sudo_local'
item "Password immediately after sleep (System Settings > Lock Screen)" 'sysadminctl -screenLock status 2>&1 | grep -q immediate'
item "No guest user" '[[ $(defaults read $LW GuestEnabled 2>/dev/null) != 1 ]]' 'defaults write $LW GuestEnabled -bool false'
item "No automatic login" '! defaults read $LW autoLoginUser' 'defaults delete $LW autoLoginUser'
item "Remote Login, File and Screen Sharing off (System Settings > General > Sharing)" \
  '! grep -qE "\.(22|445|548|3283|5900) " <<<"$LISTEN"'
# The old defaults key (AirplayRecieverEnabled) no longer has an effect on macOS 27
item "AirPlay Receiver off, ports 5000/7000 (System Settings > General > AirDrop & Handoff)" \
  '! grep -qE "\.(5000|7000) " <<<"$LISTEN"'

# Updates: everything automatic
for key in AutomaticCheckEnabled AutomaticDownload AutomaticallyInstallMacOSUpdates CriticalUpdateInstall ConfigDataInstall; do
  item "Software update: $key" '[[ $(defaults read $SU '$key' 2>/dev/null) != 0 ]]' \
    'defaults write $SU '$key' -bool true'
done

# Privacy: no analytics to Apple or app developers
item "No analytics to Apple" '[[ $(defaults read "$CR" AutoSubmit) == 0 ]]' 'defaults write "$CR" AutoSubmit -bool false'
item "No analytics to app developers" '[[ $(defaults read "$CR" ThirdPartyDataSubmit) == 0 ]]' \
  'defaults write "$CR" ThirdPartyDataSubmit -bool false'

# Power and name
item "Display sleep after 5 minutes (battery and power adapter)" \
  '[[ $(pmset -g custom | awk "/displaysleep/ {print \$2}" | sort -u) == 5 ]]' 'pmset -a displaysleep 5'
for n in ComputerName LocalHostName HostName; do
  item "$n is $NAME" '[[ $(scutil --get '$n') == "$NAME" ]]' 'scutil --set '$n' "$NAME"'
done

exit "$drift"
