#!/usr/bin/env bash
# macOS settings as code: only what differs from a fresh macOS (or is pinned on purpose).
#   macos/defaults.sh           apply (install.sh runs this), restarts Dock/Finder/Control Center if needed
#   macos/defaults.sh --check   only report settings that differ from this file, exit 1 if any
# Find the key for a new setting: `defaults read > before`, change it in System Settings,
# `defaults read > after`, `diff before after`; then add a pref line below.
# System-wide settings that need root are in macos/system.sh, the Dock's apps in macos/dock.sh.
set -euo pipefail

mode="${1:-apply}"
drift=0
changed=()

# pref <domain> <key> <bool|int|float|string> <value>; hpref: the same for per-machine (ByHost) settings
pref() { _pref "" "$@"; }
hpref() { _pref -currentHost "$@"; }
_pref() {
  local flags=() domain="$2" key="$3" type="$4" want="$5" have cmp="$5"
  [[ -n $1 ]] && flags=("$1")
  have="$(defaults ${flags[@]+"${flags[@]}"} read "$domain" "$key" 2>/dev/null || echo "<unset>")"
  [[ $type == bool ]] && { [[ $want == true ]] && cmp=1 || cmp=0; }
  [[ $have == "$cmp" ]] && return
  if [[ $mode == --check ]]; then
    echo "  $domain $key: $have (repo: $want)"
    drift=1
  else
    defaults ${flags[@]+"${flags[@]}"} write "$domain" "$key" "-$type" "$want"
    echo "  set $domain $key = $want"
    changed+=("$domain")
  fi
}

# Appearance
pref NSGlobalDomain AppleInterfaceStyle string Dark
pref NSGlobalDomain AppleShowAllExtensions bool true
pref NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true  # expanded save and print dialogs
pref NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 bool true
pref NSGlobalDomain PMPrintingExpandedStateForPrint bool true
pref NSGlobalDomain PMPrintingExpandedStateForPrint2 bool true
hpref com.apple.controlcenter BatteryShowPercentage bool true

# Keyboard and trackpad
pref NSGlobalDomain InitialKeyRepeat int 15  # fastest settings in System Settings
pref NSGlobalDomain KeyRepeat int 2
pref NSGlobalDomain ApplePressAndHoldEnabled bool false  # holding a key repeats it (umlauts have their own keys)
pref NSGlobalDomain AppleKeyboardUIMode int 2            # Tab moves through all controls
pref NSGlobalDomain com.apple.swipescrolldirection bool false  # no "natural" scrolling
pref NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool false  # straight quotes and dashes, so
pref NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool false   # pasted commands and code still work
pref NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool false

# Dock and Spaces
pref com.apple.dock autohide bool true
pref com.apple.dock show-recents bool false
pref com.apple.dock tilesize float 64
pref com.apple.dock show-process-indicators bool true   # dots under open apps (they also show when not pinned)
pref com.apple.dock mru-spaces bool false               # Spaces keep their order
pref com.apple.dock wvous-br-corner int 1  # bottom right hot corner off (default: Quick Note)
pref com.apple.dock wvous-br-modifier int 0

# Windows
pref com.apple.WindowManager EnableTiledWindowMargins bool false
pref com.apple.WindowManager EnableStandardClickToShowDesktop bool false  # clicking the wallpaper does nothing

# Finder
pref com.apple.finder FXPreferredViewStyle string Nlsv  # list view
pref com.apple.finder NewWindowTarget string PfLo       # new windows open ~/Documents
pref com.apple.finder NewWindowTargetPath string "file://$HOME/Documents/"
pref com.apple.finder ShowPathbar bool true
pref com.apple.finder ShowStatusBar bool true
pref com.apple.finder FXDefaultSearchScope string SCcf  # search the current folder
pref com.apple.finder FXEnableExtensionChangeWarning bool false
pref com.apple.finder _FXSortFoldersFirst bool true
pref com.apple.finder FXRemoveOldTrashItems bool true   # empty Trash after 30 days
pref com.apple.desktopservices DSDontWriteNetworkStores bool true  # no .DS_Store on shares and USB drives
pref com.apple.desktopservices DSDontWriteUSBStores bool true

# Devices, sharing, privacy
hpref com.apple.ImageCapture disableHotPlug bool true             # Photos doesn't open when an iPhone is connected
pref com.apple.TimeMachine DoNotOfferNewDisksForBackup bool true  # backups are restic
pref com.apple.AdLib allowApplePersonalizedAdvertising bool false

# Apps
pref io.tailscale.ipn.macsys TailscaleStartOnLogin bool true
pref io.tailscale.ipn.macsys SUAutomaticallyUpdate bool true

if [[ $mode == --check ]]; then
  exit "$drift"
fi
# Running apps only pick up their own changed settings after a restart (each process once)
restart=()
for d in ${changed[@]+"${changed[@]}"}; do
  case $d in
    com.apple.dock) restart+=(Dock) ;;
    com.apple.finder | com.apple.desktopservices) restart+=(Finder) ;;
    com.apple.controlcenter) restart+=(ControlCenter) ;;
    NSGlobalDomain | com.apple.WindowManager) restart+=(logout) ;;
  esac
done
for p in $(printf '%s\n' ${restart[@]+"${restart[@]}"} | sort -u); do
  if [[ $p == logout ]]; then echo "  some changes only apply after logging out and back in"; else killall "$p" 2>/dev/null || true; fi
done
