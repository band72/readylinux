#!/usr/bin/env bash
# ReadyLinux — install
#
# Supported:
#   Ubuntu GNOME, Zorin, Linux Mint Cinnamon / MATE / Xfce,
#   Pop!_OS COSMIC, Fedora Workstation.
#
# Run:
#   wget -qO- https://raw.githubusercontent.com/robbraxman/readylinux/main/install.sh | bash
#
# What is the same on every distro:
#   Packages: Brave, Chrome, Firefox, Thunderbird, KeePassXC, KolourPaint, VLC.
#   Folders: ~/Media/Disks and ~/Documents/AppFiles, plus a sidebar bookmark.
#   USB watcher: refreshes Media when a disk is plugged in.
#   Find my file, Brax.me launcher, AppImage click-to-install.
#   Defaults: Brave for web, Thunderbird for mail, VLC for video.
#   IPv4 preferred, IPv6 left on. Lid sleeps on battery, stays awake on AC.
#
# What changes by distro or desktop:
#   Packages: apt on Ubuntu-family, dnf on Fedora. Fedora also installs Dash to Dock.
#   Dock: GNOME favorite-apps on Ubuntu, Zorin, Fedora. Cinnamon, MATE, and Xfce
#         use their own panel. COSMIC uses its own favorites file. Zorin’s layout
#         is not moved. Xfce pins are inserted, never a full panel rewrite.
#   Fedora has no dock until Dash to Dock is enabled. Icons are 40px.
#   Wallpaper: GNOME picture-uri, MATE picture-filename, Xfce per-monitor backdrop.
#   Terminal: Ptyxis on new Ubuntu, GNOME Terminal on Zorin and Mint, xfce4-terminal
#             on Xfce. Size 110x34, or 120x36 on Xfce. Colors are not forced.
#   Editor: GNOME Text Editor, or Xed on Mint. Font 12pt.
#   Scale: 125% on a laptop or 1080p. 100% on a 1440p or 4K desktop.
#   File manager: Nautilus, Nemo, Caja, Thunar, or COSMIC Files. Bookmarks are GTK.
#
# Known limits:
#   Zorin: panel layout is not touched. Pins are added only. Moving Zorin's
#          panel or taskbar breaks its Windows-style setup.
#   Xfce: the panel list is never rewritten. Replacing plugin-ids moves the
#         tray and leaves dead Show Apps icons. Pins are inserted if the
#         panel is already a normal launcher panel. Thunar does not remember
#         window position. Wallpaper is set per monitor and can miss if the
#         backdrop path is not the usual screen0/monitor path.
#   Fedora: custom partitioning is an Anaconda bug. Use a whole disk.
#            There is no dock until Dash to Dock is enabled.
#   GNOME: dock clicks can freeze until a logout after pins are written.
#   Colors are not forced on any terminal. The user keeps their palette.
#
# Mint's file manager may run this with sh. sh would fail on the bash syntax below.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# ---------------------------------------------------------------------------
# Helpers
# Defined at the top level so the tests can load them with READYLINUX_TEST=1.
# ---------------------------------------------------------------------------
KIT_VERSION="2026.10.24"
KIT_DIR="$HOME/.local/share/human-linux"
KIT_STAMP="$KIT_DIR/version"
KIT_SETTINGS="$KIT_DIR/settings.json"

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }

desktop_session() {
  printf '%s\n' "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

# A rerun checks what is there. Kit files are compared before writing, and
# each one is reported as new, updated, or up to date in the summary.
KIT_NEW=()
KIT_UPDATED=()
KIT_SAME=0
# put_file DEST [sudo] < content
# Writes DEST only when the content differs. KIT_CHANGED is 1 if it did.
KIT_CHANGED=0
put_file() {
  local dest="$1" as="${2:-}" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  KIT_CHANGED=0
  if [[ -f "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    KIT_SAME=$((KIT_SAME + 1))
    return 0
  fi
  KIT_CHANGED=1
  if [[ -f "$dest" ]]; then
    KIT_UPDATED+=("$dest")
    printf '    updated   %s\n' "$dest"
  else
    KIT_NEW+=("$dest")
    printf '    installed %s\n' "$dest"
  fi
  if [[ "$as" == "sudo" ]]; then
    sudo mkdir -p "$(dirname "$dest")"
    sudo tee "$dest" < "$tmp" >/dev/null
  else
    mkdir -p "$(dirname "$dest")"
    cat "$tmp" > "$dest"
  fi
  rm -f "$tmp"
}

# gset_once SCHEMA[:PATH] KEY VALUE [SCHEMA KEY VALUE ...]
# Sets a GSettings key only if the user has never changed it, or if it still
# holds the value the kit set last time. A value the user picked is kept.
# What the kit set is remembered in ~/.local/share/human-linux/settings.json.
gset_once() {
  need_cmd python3 || return 0
  python3 - "$KIT_SETTINGS" "$@" <<'PY' || true
import json, sys
from pathlib import Path
try:
    import gi
    from gi.repository import Gio, GLib
except Exception:
    raise SystemExit(0)
state = Path(sys.argv[1])
args = sys.argv[2:]
try:
    seen = json.loads(state.read_text())
except Exception:
    seen = {}
source = Gio.SettingsSchemaSource.get_default()
for i in range(0, len(args) - 2, 3):
    spec, key, text = args[i:i + 3]
    schema_id, _, path = spec.partition(":")
    schema = source.lookup(schema_id, True) if source else None
    if schema is None or not schema.has_key(key):
        continue
    settings = Gio.Settings.new_full(schema, None, path or None)
    if not settings.is_writable(key):
        continue
    try:
        want = GLib.Variant.parse(schema.get_key(key).get_value_type(), text, None, None)
    except GLib.Error as e:
        print(f"    bad value for {schema_id} {key}: {text} ({e.message})")
        continue
    tag = f"{spec} {key}"
    user = settings.get_user_value(key)
    if user is not None and user.equal(want):
        seen[tag] = want.print_(False)
        continue
    if user is not None and user.print_(False) != seen.get(tag):
        print(f"    kept      {schema_id} {key} = {user.print_(False)} (your setting)")
        continue
    settings.set_value(key, want)
    seen[tag] = want.print_(False)
    print(f"    set       {schema_id} {key} = {want.print_(False)}")
Gio.Settings.sync()
state.parent.mkdir(parents=True, exist_ok=True)
state.write_text(json.dumps(seen, indent=1, sort_keys=True) + "\n")
PY
}

# fetch_image URL DEST
# Downloads to a temp file and keeps it only if it is a JPEG or PNG under 20 MB.
# An error page, a redirect to HTML, or a truncated file is thrown away.
fetch_image() {
  local url="$1" dest="$2" tmp magic
  tmp="$(mktemp)"
  if curl -fsSL --max-filesize 20000000 -o "$tmp" "$url"; then
    magic="$(head -c 4 "$tmp" | od -An -tx1 | tr -d ' \n')"
    case "$magic" in
      ffd8ff*|89504e47)
        mkdir -p "$(dirname "$dest")"
        install -m 644 "$tmp" "$dest"
        rm -f "$tmp"
        return 0
        ;;
    esac
    warn "$url is not a JPEG or PNG. Skipped."
  fi
  rm -f "$tmp"
  return 1
}

# ---------------------------------------------------------------------------
# The whole install is one function, called on the last line. When the script
# is piped into bash, a download cut off part way defines nothing and runs
# nothing, and no command can read the rest of the script from stdin.
# ---------------------------------------------------------------------------
main() {
# Double-click in Files does nothing useful. Use install.desktop, or run in a terminal.
if [[ ! -t 1 ]]; then
  if [[ -f "$KIT_STAMP" ]]; then
    intro="ReadyLinux $(head -n1 "$KIT_STAMP") is already installed. This is $KIT_VERSION.\n\nIt checks each app and kit file, installs what is missing, and updates what is out of date. Nothing up to date is touched."
  else
    intro="This installs KeePassXC, KolourPaint, Chrome, VLC, Thunderbird, GDebi, Disks, and Flatpak.\n\nIt also sets folders, the dock, the lid rule, and Find my file."
  fi
  zenity --question --width=420 --title="ReadyLinux" \
    --text="$intro\n\nA terminal will open so you can enter your password. Continue?" \
    || exit 0
  term="$(command -v gnome-terminal || command -v x-terminal-emulator || true)"
  [[ -n "$term" ]] || { zenity --error --text="No terminal found."; exit 1; }
  exec "$term" -- bash -c "\"$0\"; echo; read -r -p 'Press Enter to close.'"
fi
set -euo pipefail

SCALE="1.25"
WALLPAPER_URL="https://brax.me/readylinux/wallpaper.jpg"
BRAX_ICON_URL="https://brax.me/img/logo-b1a.png"
BRAX_URL="https://brax.me"

if [[ "$(id -u)" -eq 0 ]]; then
  warn "Run as your user, not root. The script will ask for sudo."
  exit 1
fi

if [[ -f "$KIT_STAMP" ]]; then
  KIT_PREV="$(head -n1 "$KIT_STAMP")"
  log "ReadyLinux $KIT_PREV found. Checking for missing or outdated items ($KIT_VERSION)."
else
  KIT_PREV=""
  log "ReadyLinux $KIT_VERSION, first run"
fi
# Private scratch space. Fixed names in /tmp can be pre-created by another user.
KIT_TMP="$(mktemp -d)"
trap 'rm -rf "$KIT_TMP"' EXIT

# ---------------------------------------------------------------------------
# System packages
# Fedora uses dnf. Everything else uses apt.
# Chrome and Brave are added from their own repos. Fedora 41+ needs the
# dnf5 repo command. Cinnamon also gets Xed. Fedora gets Dash to Dock.
# ---------------------------------------------------------------------------
log "Checking packages"
. /etc/os-release
# Each package is reported as ok, update, or missing. Only missing ones are
# installed and only outdated ones are upgraded, so a rerun is quick.
PKG_MISSING=()
PKG_OUTDATED=()
pkg_report() {
  local p state
  for p in "$@"; do
    state="ok"
    if [[ " ${PKG_MISSING[*]} " == *" $p "* ]]; then state="missing"
    elif [[ " ${PKG_OUTDATED[*]} " == *" $p "* ]]; then state="update"
    fi
    printf '    %-8s %s\n' "$state" "$p"
  done
}
case "${ID:-}" in
  fedora)
    pkgs=(curl ca-certificates wget gnupg2 zenity flatpak python3-gobject gtk3
          keepassxc kolourpaint thunderbird firefox vlc gnome-text-editor gnome-disk-utility
          gnome-shell-extension-dash-to-dock)
    # Chrome comes from Google's repo with gpgcheck on, not a bare .rpm URL.
    # dnf does not check signatures on a package given by URL.
    if ! rpm -q google-chrome-stable >/dev/null 2>&1; then
      log "Adding the Google Chrome repo"
      sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
      put_file /etc/yum.repos.d/google-chrome.repo sudo <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
    fi
    if ! rpm -q brave-browser >/dev/null 2>&1 && [[ ! -f /etc/yum.repos.d/brave-browser.repo ]]; then
      log "Adding the Brave repo"
      sudo dnf install -y dnf-plugins-core
      if dnf config-manager --help 2>&1 | grep -q addrepo; then
        sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
      else
        sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
      fi
    fi
    pkgs+=(google-chrome-stable brave-browser)
    pkg_have=()
    for p in "${pkgs[@]}"; do
      if rpm -q "$p" >/dev/null 2>&1; then pkg_have+=("$p"); else PKG_MISSING+=("$p"); fi
    done
    if ((${#pkg_have[@]})); then
      while read -r p; do
        [[ -n "$p" ]] && PKG_OUTDATED+=("$p")
      done < <(sudo dnf -q list --upgrades "${pkg_have[@]}" 2>/dev/null \
                 | awk '$1 ~ /\./ { sub(/\.[^.]+$/, "", $1); print $1 }' | sort -u)
    fi
    pkg_report "${pkgs[@]}"
    if ((${#PKG_MISSING[@]})); then
      log "Installing ${#PKG_MISSING[@]} missing package(s)"
      sudo dnf install -y "${PKG_MISSING[@]}"
    fi
    if ((${#PKG_OUTDATED[@]})); then
      log "Updating ${#PKG_OUTDATED[@]} package(s)"
      sudo dnf upgrade -y "${PKG_OUTDATED[@]}"
    fi
    ;;
  *)
    pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
    pkgs=(curl ca-certificates wget gnupg zenity flatpak gdebi gnome-disk-utility
          python3-gi gir1.2-gtk-3.0
          keepassxc kolourpaint thunderbird firefox vlc)
    if pkg_installed gnome-text-editor; then pkgs+=(gnome-text-editor)
    elif pkg_installed gedit; then pkgs+=(gedit)
    elif apt-cache show gnome-text-editor >/dev/null 2>&1; then pkgs+=(gnome-text-editor)
    else pkgs+=(gedit)
    fi
    if [[ "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" == *[Cc]innamon* ]]; then
      pkgs+=(xed)
    fi
    if [[ ! -f /etc/apt/sources.list.d/google-chrome.list ]] && ! pkg_installed google-chrome-stable; then
      log "Adding the Google Chrome repo"
      sudo mkdir -p /usr/share/keyrings
      curl -fsSL -o "$KIT_TMP/google-chrome.pub" https://dl.google.com/linux/linux_signing_key.pub
      sudo rm -f /usr/share/keyrings/google-chrome.gpg
      sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/google-chrome.gpg "$KIT_TMP/google-chrome.pub"
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        | sudo tee /etc/apt/sources.list.d/google-chrome.list >/dev/null
    fi
    if [[ ! -f /etc/apt/sources.list.d/brave-browser-release.list ]] && ! pkg_installed brave-browser; then
      log "Adding the Brave repo"
      sudo mkdir -p /usr/share/keyrings
      curl -fsSL -o "$KIT_TMP/brave-browser-archive-keyring.gpg" \
        https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
      sudo install -m 644 "$KIT_TMP/brave-browser-archive-keyring.gpg" /usr/share/keyrings/brave-browser-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
        | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
    fi
    pkgs+=(google-chrome-stable brave-browser)
    sudo apt-get update
    upgradable=" $(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 {printf "%s ", $1}')"
    for p in "${pkgs[@]}"; do
      if ! pkg_installed "$p"; then PKG_MISSING+=("$p")
      elif [[ "$upgradable" == *" $p "* ]]; then PKG_OUTDATED+=("$p")
      fi
    done
    pkg_report "${pkgs[@]}"
    if ((${#PKG_MISSING[@]})); then
      log "Installing ${#PKG_MISSING[@]} missing package(s)"
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKG_MISSING[@]}" || {
        # One bad name (an editor or xed not in this release) should not stop the rest.
        warn "Batch install failed. Trying one at a time."
        for p in "${PKG_MISSING[@]}"; do
          sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$p" || warn "Could not install $p"
        done
      }
    fi
    if ((${#PKG_OUTDATED[@]})); then
      log "Updating ${#PKG_OUTDATED[@]} package(s)"
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade "${PKG_OUTDATED[@]}" \
        || warn "Some updates failed. Run Software Updater."
    fi
    ;;
esac

if ! flatpak remotes | grep -q flathub; then
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Ubuntu Snap Thunderbird stores mail outside the apt profile.
# Copy it when the apt profile is missing or still blank. Do not overwrite accounts.
snap_tb="$HOME/snap/thunderbird/common/.thunderbird"
if [[ -f "$snap_tb/profiles.ini" ]]; then
  blank=1
  if [[ -f "$HOME/.thunderbird/profiles.ini" ]]; then
    if grep -Rqs 'mail.accountmanager.accounts' "$HOME/.thunderbird" 2>/dev/null \
       && grep -Rqs 'mail.accountmanager.accounts=.*[a-zA-Z0-9]' "$HOME/.thunderbird" 2>/dev/null; then
      blank=0
    fi
  fi
  if [[ "$blank" == "1" ]]; then
    log "Copying Snap Thunderbird profile into the blank apt profile"
    mkdir -p "$HOME/.thunderbird"
    cp -a "$snap_tb"/. "$HOME/.thunderbird"/
  fi
fi
if [[ -f /etc/gai.conf ]] && grep -q 'human-linux-ipv4' /etc/gai.conf; then
  log "IPv4 preference already set"
else
  log "Prefer IPv4, leave IPv6 available"
  echo "precedence ::ffff:0:0/96  100  # human-linux-ipv4" | sudo tee -a /etc/gai.conf >/dev/null
fi

# Lid: suspend on battery, awake on AC and dock. Do not restart logind.
log "Lid close rule (applies on next reboot)"
sudo mkdir -p /etc/systemd/logind.conf.d
put_file /etc/systemd/logind.conf.d/human-linux-lid.conf sudo <<'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF

# ---------------------------------------------------------------------------
# Folders and sidebar
# Same on every distro. ~/Media/Disks links extra disks and USB.
# ~/Documents/AppFiles links Snap, Flatpak, debs, and rpms.
# Bookmarks are GTK, so Nautilus, Nemo, Caja, and Thunar all see them.
# KDE places are written later, in the desktop branch.
# ---------------------------------------------------------------------------
refresh_appfiles() {
  local dest="$HOME/Documents/AppFiles" d name
  mkdir -p "$dest" "$dest/debs" "$dest/rpms" "$dest/appimages"
  if [[ -d "$HOME/snap" ]]; then
    for d in "$HOME/snap"/*; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      [[ "$name" == "README" ]] && continue
      [[ -e "$d/current" ]] && ln -sfn "$d/current" "$dest/${name}"
      [[ -d "$d/common" ]] && ln -sfn "$d/common" "$dest/${name}-common"
    done
  fi
  if [[ -d "$HOME/.var/app" ]]; then
    for d in "$HOME/.var/app"/*; do
      [[ -d "$d" ]] || continue
      name="$(basename "$d")"
      ln -sfn "$d" "$dest/flatpak-${name}"
    done
  fi
  if [[ -d "$HOME/Downloads" ]]; then
    for d in "$HOME/Downloads"/*.deb "$HOME/Downloads"/*.Deb; do
      [[ -e "$d" ]] || continue
      ln -sfn "$d" "$dest/debs/$(basename "$d")"
    done
    for d in "$HOME/Downloads"/*.rpm "$HOME/Downloads"/*.RPM; do
      [[ -e "$d" ]] || continue
      ln -sfn "$d" "$dest/rpms/$(basename "$d")"
    done
  fi
}

bookmark() {
  local uri="$1" label="$2" f
  for f in "$HOME/.config/gtk-3.0/bookmarks" "$HOME/.config/gtk-4.0/bookmarks"; do
    mkdir -p "$(dirname "$f")"
    touch "$f"
    grep -qF "$uri" "$f" || echo "$uri $label" >> "$f"
  done
}

log "Folders and sidebar"
xdg-user-dirs-update || true
mkdir -p "$HOME/Media/Disks" "$HOME/Videos/OBS" "$HOME/Documents/AppFiles"
refresh_appfiles
bookmark "file://$HOME/Media" "Media"
bookmark "file://$HOME/Documents/AppFiles" "AppFiles"
bookmark "file:///" "File System"

# ---------------------------------------------------------------------------
# USB watcher
# User systemd service. Refreshes Media on udisks events, and once a minute.
# Same on every distro. Needs a desktop login, not a raw TTY.
# ---------------------------------------------------------------------------
log "USB watcher"
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
put_file "$HOME/.local/bin/human-linux-usb-watch" <<'EOF'
#!/usr/bin/env bash
refresh() {
  local user src d gvfs mtp dev mp fstype
  user="$(id -un)"
  mkdir -p "$HOME/Media/Disks"
  if command -v lsblk >/dev/null && command -v udisksctl >/dev/null; then
    while read -r dev fstype label mp; do
      [[ -n "$dev" && -n "$fstype" ]] || continue
      [[ "$fstype" == "swap" || "$fstype" == "iso9660" ]] && continue
      case "$mp" in
        /|/boot|/boot/efi|/home) continue ;;
      esac
      [[ -n "$mp" ]] && continue
      case "${label,,}" in
        boot|efi|esp|system|recovery|winre|winre_drv|"microsoft reserved"|reserved) continue ;;
      esac
      udisksctl mount -b "$dev" >/dev/null 2>&1 || true
    done < <(lsblk -pnr -o PATH,FSTYPE,LABEL,MOUNTPOINT)
  fi
  find "$HOME/Media/Disks" -maxdepth 1 -type l -delete 2>/dev/null || true
  find "$HOME/Media/USB" -maxdepth 1 -type l -delete 2>/dev/null || true
  rmdir "$HOME/Media/USB" 2>/dev/null || true
  for src in "/media/$user" "/run/media/$user"; do
    [[ -d "$src" ]] || continue
    for d in "$src"/*; do
      [[ -e "$d" ]] || continue
      case "$(basename "$d" | tr '[:upper:]' '[:lower:]')" in
        boot|efi|esp|system|recovery|winre|winre_drv) continue ;;
      esac
      ln -sfn "$d" "$HOME/Media/Disks/$(basename "$d")"
    done
  done
  gvfs="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
  rm -f "$HOME/Media/Phone"
  if [[ -d "$gvfs" ]]; then
    mtp="$(find "$gvfs" -maxdepth 1 \( -iname '*mtp*' -o -iname '*gphoto*' -o -iname '*afc*' \) 2>/dev/null | head -n1 || true)"
    if [[ -n "${mtp:-}" && -e "$mtp" ]]; then
      ln -sfn "$mtp" "$HOME/Media/Phone"
    fi
  fi
}
refresh
[[ "${1:-}" == "--once" ]] && exit 0
# udisks events do the work. The slow poll only catches a missed event.
( while true; do sleep 60; refresh; done ) &
udisksctl monitor | while read -r line; do
  case "$line" in
    *Added*|*Removed*|*mounted*|*Properties\ Changed*) refresh ;;
  esac
done
EOF
watch_changed=$KIT_CHANGED
chmod +x "$HOME/.local/bin/human-linux-usb-watch"
# The installer uses the watcher's own code to make the Media links now.
"$HOME/.local/bin/human-linux-usb-watch" --once || true
put_file "$HOME/.config/systemd/user/human-linux-usb-watch.service" <<EOF
[Unit]
Description=Refresh ReadyLinux Media links
After=graphical-session.target
[Service]
ExecStart=$HOME/.local/bin/human-linux-usb-watch
Restart=always
RestartSec=3
[Install]
WantedBy=default.target
EOF
watch_changed=$((watch_changed | KIT_CHANGED))
systemctl --user disable --now usb-watch.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/usb-watch.service" "$HOME/.local/bin/usb-watch"
systemctl --user daemon-reload || true
systemctl --user enable human-linux-usb-watch.service || true
if [[ "$watch_changed" == "1" ]] || ! systemctl --user is-active --quiet human-linux-usb-watch.service; then
  systemctl --user restart human-linux-usb-watch.service || warn "Disk watcher not started. Log in on the desktop and rerun."
else
  echo "    disk watcher running and up to date"
fi

# ---------------------------------------------------------------------------
# Find my file
# A small search GUI in Show Apps. Same on every distro.
# ---------------------------------------------------------------------------
log "Find my file"
# One Python program. With a name it prints matches in a terminal.
# With no name it opens a GTK form: Documents, Downloads, Home folder, All.
# It falls back to zenity dialogs if the GTK bindings are missing.
put_file "$HOME/.local/bin/where-is-my-file" <<'PYAPP'
#!/usr/bin/env python3
# Find my file. A search form for the user's own folders.
#   where-is-my-file                     open the window
#   where-is-my-file [--documents] [--downloads] [--home] [--all] NAME
#                                        print matches in a terminal
# Documents and Downloads are the default. Home is everything under ~.
# All adds the disks and phone under ~/Media, and Snap and Flatpak app files.
import os
import re
import subprocess
import sys
import threading
import time

HOME = os.path.expanduser("~")
LIMIT = 1000


def user_dir(key, fallback):
    # Localized names come from xdg-user-dirs, e.g. ~/Documentos.
    try:
        with open(os.path.join(HOME, ".config/user-dirs.dirs")) as f:
            for line in f:
                m = re.match(r'\s*XDG_%s_DIR="(.*)"' % key, line)
                if m:
                    return m.group(1).replace("$HOME", HOME)
    except OSError:
        pass
    return os.path.join(HOME, fallback)


DOCUMENTS = user_dir("DOCUMENTS", "Documents")
DOWNLOADS = user_dir("DOWNLOAD", "Downloads")


def roots_for(scopes):
    if "all" in scopes or "home" in scopes:
        roots = [HOME]
    else:
        roots = []
        if "documents" in scopes:
            roots.append(DOCUMENTS)
        if "downloads" in scopes:
            roots.append(DOWNLOADS)
    return [r for r in roots if os.path.isdir(r)]


def search(query, scopes, stop=None):
    """Yield matching paths. Case-insensitive, plain text, no wildcards.
    Hidden folders are skipped. Links are followed, each folder is visited
    once, and outside ~ only when All is checked (USB disks, phone)."""
    needle = query.lower()
    outside_ok = "all" in scopes
    seen = set()
    for root in roots_for(scopes):
        for top, dirs, files in os.walk(root, followlinks=True, onerror=None):
            if stop is not None and stop.is_set():
                return
            try:
                st = os.stat(top)
            except OSError:
                dirs[:] = []
                continue
            if (st.st_dev, st.st_ino) in seen:
                dirs[:] = []
                continue
            seen.add((st.st_dev, st.st_ino))
            real = os.path.realpath(top)
            if not outside_ok and real != HOME and not real.startswith(HOME + os.sep):
                dirs[:] = []
                continue
            dirs[:] = sorted(d for d in dirs if not d.startswith("."))
            for name in dirs + sorted(f for f in files if not f.startswith(".")):
                if needle in name.lower():
                    yield os.path.join(top, name)


def human_size(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def cli(argv):
    scopes = {a[2:] for a in argv if a.startswith("--")}
    words = [a for a in argv if not a.startswith("--")]
    bad = scopes - {"documents", "downloads", "home", "all"}
    if not words or bad:
        print("usage: where-is-my-file [--documents] [--downloads] [--home] [--all] <name>")
        return 1
    scopes = scopes or {"documents", "downloads"}
    found = 0
    for path in search(" ".join(words), scopes):
        print(path)
        found += 1
        if found >= LIMIT:
            print(f"... stopped at {LIMIT} matches", file=sys.stderr)
            break
    return 0 if found else 1


def zenity_gui():
    # No GTK bindings. Same form, built from zenity dialogs.
    def z(*args):
        r = subprocess.run(["zenity", *args], capture_output=True, text=True)
        return r.returncode, r.stdout.strip()
    rc, query = z("--entry", "--title=Find my file", "--text=Name or part of a name",
                  "--ok-label=Next", "--cancel-label=Cancel")
    if rc != 0 or not query:
        return 0
    rc, picked = z("--list", "--checklist", "--title=Find my file", "--text=Search in",
                   "--column=", "--column=Where", "--column=key", "--hide-column=3",
                   "--print-column=3", "--separator= ", "--height=300", "--ok-label=Search",
                   "TRUE", "Documents", "documents", "TRUE", "Downloads", "downloads",
                   "FALSE", "Home folder (everything in it)", "home",
                   "FALSE", "All (home, USB disks, phone, app files)", "all")
    if rc != 0:
        return 0
    scopes = set(picked.split()) or {"documents", "downloads"}
    hits = []
    for p in search(query, scopes):
        hits.append(p)
        if len(hits) >= LIMIT:
            break
    if not hits:
        z("--info", "--title=Find my file", "--text=No matches for: " + query.replace("&", "&amp;").replace("<", "&lt;"))
        return 0
    args = ["--list", f"--title=Find my file: {len(hits)} found", "--text=Pick a file and press Open",
            "--column=Name", "--column=Folder", "--column=path", "--hide-column=3",
            "--print-column=3", "--width=800", "--height=500", "--ok-label=Open", "--cancel-label=Close"]
    for p in hits:
        args += [os.path.basename(p), os.path.dirname(p), p]
    rc, path = z(*args)
    if rc == 0 and path:
        subprocess.Popen(["xdg-open", path.split("|")[0]])
    return 0


def gtk_gui():
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    class Finder(Gtk.Window):
        def __init__(self):
            super().__init__(title="Find my file")
            self.set_default_size(900, 600)
            self.set_icon_name("readylinux-find-my-file")
            self.stop = threading.Event()
            self.job = 0

            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin=14)
            self.add(box)

            row = Gtk.Box(spacing=8)
            row.pack_start(Gtk.Label(label="Name or part of a name:"), False, False, 0)
            self.entry = Gtk.SearchEntry()
            self.entry.connect("activate", self.on_search)
            row.pack_start(self.entry, True, True, 0)
            self.search_btn = Gtk.Button(label="Search")
            self.search_btn.get_style_context().add_class("suggested-action")
            self.search_btn.connect("clicked", self.on_search)
            row.pack_start(self.search_btn, False, False, 0)
            self.stop_btn = Gtk.Button(label="Stop", sensitive=False)
            self.stop_btn.connect("clicked", lambda *_: self.stop.set())
            row.pack_start(self.stop_btn, False, False, 0)
            box.pack_start(row, False, False, 0)

            frame = Gtk.Frame(label="Search in")
            checks = Gtk.Box(spacing=18, margin=8)
            frame.add(checks)
            self.checks = {}
            for key, label, tip, on in (
                ("documents", "Documents", DOCUMENTS, True),
                ("downloads", "Downloads", DOWNLOADS, True),
                ("home", "Home folder", "Everything in " + HOME + ", except hidden folders", False),
                ("all", "All", "Home, plus USB disks and phone under ~/Media, and Snap and Flatpak app files", False),
            ):
                cb = Gtk.CheckButton(label=label, active=on, tooltip_text=tip)
                cb.connect("toggled", self.on_scope)
                checks.pack_start(cb, False, False, 0)
                self.checks[key] = cb
            box.pack_start(frame, False, False, 0)

            # name, folder, modified, size, path, mtime, bytes
            self.store = Gtk.ListStore(str, str, str, str, str, float, GLib.TYPE_INT64)
            self.view = Gtk.TreeView(model=self.store)
            for i, (title, sort_col, expand) in enumerate((
                ("Name", 0, True), ("Folder", 1, True), ("Modified", 5, False), ("Size", 6, False),
            )):
                cell = Gtk.CellRendererText(ellipsize=3 if i < 2 else 0)
                col = Gtk.TreeViewColumn(title, cell, text=i)
                col.set_sort_column_id(sort_col)
                col.set_resizable(True)
                col.set_expand(expand)
                self.view.append_column(col)
            self.view.connect("row-activated", lambda *_: self.open_selected())
            self.view.get_selection().connect("changed", self.on_select)
            scroll = Gtk.ScrolledWindow(hexpand=True, vexpand=True)
            scroll.add(self.view)
            box.pack_start(scroll, True, True, 0)

            bottom = Gtk.Box(spacing=8)
            self.status = Gtk.Label(label="Type a name, pick where to look, press Search.", xalign=0)
            bottom.pack_start(self.status, True, True, 0)
            self.open_btn = Gtk.Button(label="Open", sensitive=False)
            self.open_btn.connect("clicked", lambda *_: self.open_selected())
            self.folder_btn = Gtk.Button(label="Show in folder", sensitive=False)
            self.folder_btn.connect("clicked", lambda *_: self.show_in_folder())
            self.copy_btn = Gtk.Button(label="Copy path", sensitive=False)
            self.copy_btn.connect("clicked", lambda *_: self.copy_path())
            for b in (self.copy_btn, self.folder_btn, self.open_btn):
                bottom.pack_end(b, False, False, 0)
            box.pack_start(bottom, False, False, 0)

            self.connect("destroy", self.on_quit)
            self.on_scope()

        # "All" covers Home, and Home covers Documents and Downloads.
        def on_scope(self, *_):
            c = self.checks
            c["home"].set_sensitive(not c["all"].get_active())
            wide = c["all"].get_active() or c["home"].get_active()
            c["documents"].set_sensitive(not wide)
            c["downloads"].set_sensitive(not wide)

        def scopes(self):
            c = self.checks
            if c["all"].get_active():
                return {"all"}
            if c["home"].get_active():
                return {"home"}
            return {k for k in ("documents", "downloads") if c[k].get_active()}

        def on_search(self, *_):
            query = self.entry.get_text().strip()
            if not query:
                self.status.set_text("Type a name first.")
                return
            scopes = self.scopes()
            if not scopes:
                self.status.set_text("Check at least one place to search.")
                return
            self.stop.set()
            self.stop = threading.Event()
            self.job += 1
            self.store.clear()
            self.found = 0
            self.search_btn.set_sensitive(False)
            self.stop_btn.set_sensitive(True)
            self.status.set_text("Searching…")
            threading.Thread(target=self.worker, args=(self.job, query, scopes, self.stop), daemon=True).start()

        def worker(self, job, query, scopes, stop):
            batch, last = [], time.monotonic()
            count = 0
            for path in search(query, scopes, stop):
                try:
                    st = os.stat(path)
                    mtime, size = st.st_mtime, st.st_size
                    is_dir = os.path.isdir(path)
                except OSError:
                    mtime, size, is_dir = 0.0, 0, False
                batch.append((path, mtime, size, is_dir))
                count += 1
                if count >= LIMIT:
                    break
                if time.monotonic() - last > 0.2:
                    GLib.idle_add(self.add_rows, job, batch)
                    batch, last = [], time.monotonic()
            GLib.idle_add(self.add_rows, job, batch)
            GLib.idle_add(self.done, job, query, count >= LIMIT, stop.is_set())

        def add_rows(self, job, batch):
            if job != self.job:
                return False
            for path, mtime, size, is_dir in batch:
                when = time.strftime("%Y-%m-%d %H:%M", time.localtime(mtime)) if mtime else ""
                shown = "folder" if is_dir else human_size(size)
                self.store.append([os.path.basename(path), os.path.dirname(path), when, shown,
                                   path, mtime, -1 if is_dir else size])
            self.found += len(batch)
            self.status.set_text(f"Searching… {self.found} found")
            return False

        def done(self, job, query, capped, stopped):
            if job != self.job:
                return False
            self.search_btn.set_sensitive(True)
            self.stop_btn.set_sensitive(False)
            if self.found == 0:
                msg = f"No matches for “{query}”."
                if not stopped and not self.checks["all"].get_active():
                    msg += " Try a wider place, like Home folder or All."
            else:
                msg = f"{self.found} found. Double-click to open."
                if capped:
                    msg = f"First {LIMIT} shown. Type more of the name to narrow it."
            if stopped:
                msg = "Stopped. " + msg
            self.status.set_text(msg)
            return False

        def selected_path(self):
            model, it = self.view.get_selection().get_selected()
            return model[it][4] if it else None

        def on_select(self, *_):
            on = self.selected_path() is not None
            for b in (self.open_btn, self.folder_btn, self.copy_btn):
                b.set_sensitive(on)

        def open_selected(self):
            path = self.selected_path()
            if path:
                try:
                    Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(path).get_uri(), None)
                except GLib.Error:
                    subprocess.Popen(["xdg-open", path])

        def show_in_folder(self):
            path = self.selected_path()
            if not path:
                return
            # FileManager1 opens the folder with the file selected. Not every file manager has it.
            try:
                bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
                bus.call_sync("org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                              "org.freedesktop.FileManager1", "ShowItems",
                              GLib.Variant("(ass)", ([Gio.File.new_for_path(path).get_uri()], "")),
                              None, Gio.DBusCallFlags.NONE, 3000, None)
            except GLib.Error:
                subprocess.Popen(["xdg-open", os.path.dirname(path)])

        def copy_path(self):
            path = self.selected_path()
            if path:
                Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(path, -1)
                self.status.set_text("Path copied.")

        def on_quit(self, *_):
            self.stop.set()
            Gtk.main_quit()

    win = Finder()
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args != ["--gui"]:
        sys.exit(cli(args))
    try:
        sys.exit(gtk_gui())
    except (ImportError, ValueError):
        sys.exit(zenity_gui())
PYAPP
chmod +x "$HOME/.local/bin/where-is-my-file"
# Kept so old menu entries and keyboard shortcuts still work.
put_file "$HOME/.local/bin/where-is-my-file-gui" <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/bin/where-is-my-file" --gui
EOF
chmod +x "$HOME/.local/bin/where-is-my-file-gui"
# Folder with a magnifier. hicolor is the fallback theme on every desktop.
icons="$HOME/.local/share/icons/hicolor"
put_file "$icons/scalable/apps/readylinux-find-my-file.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="back" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#e5a50a"/>
      <stop offset="1" stop-color="#c88800"/>
    </linearGradient>
    <linearGradient id="front" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#f8e45c"/>
      <stop offset="1" stop-color="#f6c342"/>
    </linearGradient>
    <radialGradient id="glass" cx="0.4" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.95"/>
      <stop offset="1" stop-color="#99c1f1" stop-opacity="0.85"/>
    </radialGradient>
  </defs>
  <path d="M10 26a8 8 0 0 1 8-8h28l10 10h54a8 8 0 0 1 8 8v66a8 8 0 0 1-8 8H18a8 8 0 0 1-8-8z" fill="url(#back)"/>
  <rect x="10" y="38" width="108" height="72" rx="8" fill="url(#front)"/>
  <rect x="10" y="38" width="108" height="3" fill="#ffffff" opacity="0.5"/>
  <path d="M84 84l26 26" stroke="#3d3846" stroke-width="13" stroke-linecap="round"/>
  <path d="M84 84l26 26" stroke="#5e5c64" stroke-width="7" stroke-linecap="round"/>
  <circle cx="66" cy="66" r="25" fill="url(#glass)" stroke="#1c71d8" stroke-width="7"/>
  <path d="M53 58a15 15 0 0 1 12-9" fill="none" stroke="#ffffff" stroke-width="4" stroke-linecap="round" opacity="0.9"/>
</svg>
SVG
if [[ "$KIT_CHANGED" == "1" ]]; then
  [[ -f "$icons/index.theme" ]] || cp -f /usr/share/icons/hicolor/index.theme "$icons/" 2>/dev/null || true
  gtk-update-icon-cache -f -t "$icons" >/dev/null 2>&1 || true
fi
mkdir -p "$HOME/.local/share/applications"
put_file "$HOME/.local/share/applications/where-is-my-file.desktop" <<EOF
[Desktop Entry]
Name=Find my file
GenericName=File search
Comment=Search Documents, Downloads, your Home folder, or everything including USB disks
Keywords=find;search;file;locate;where;
Exec=$HOME/.local/bin/where-is-my-file --gui
Terminal=false
Type=Application
Icon=readylinux-find-my-file
Categories=Utility;
StartupNotify=true
X-ReadyLinux=true
EOF

# ---------------------------------------------------------------------------
# Brax.me
# A site-as-app launcher. Same on every distro that has Brave or Chrome.
# ---------------------------------------------------------------------------
log "Brax.me launcher"
browser="$(command -v brave-browser || command -v google-chrome-stable || command -v google-chrome || true)"
if [[ -n "$browser" ]]; then
  mkdir -p "$HOME/.local/share/icons"
  [[ -s "$HOME/.local/share/icons/brax-me.png" ]] \
    || fetch_image "$BRAX_ICON_URL" "$HOME/.local/share/icons/brax-me.png" \
    || warn "Brax icon download failed"
  put_file "$HOME/.local/share/applications/brax-me.desktop" <<EOF
[Desktop Entry]
Name=Brax.me
Comment=brax.me
Exec=$browser --app=$BRAX_URL
Icon=$HOME/.local/share/icons/brax-me.png
Terminal=false
Type=Application
Categories=Network;
StartupNotify=true
X-ReadyLinux=true
EOF
fi

# ---------------------------------------------------------------------------
# Defaults
# Brave for http/https, Thunderbird for mailto, VLC for video.
# .deb opens in GDebi on apt distros. .rpm opens in GNOME Software on Fedora.
# .iso opens in Disks. .sh opens the Run or Edit launcher.
# ---------------------------------------------------------------------------
desktop_id_exists() {
  local id="$1" f
  for f in "/usr/share/applications/${id}" "$HOME/.local/share/applications/${id}" \
           "/var/lib/flatpak/exports/share/applications/${id}"; do
    [[ -f "$f" ]] && return 0
  done
  return 1
}
first_existing_desktop() {
  local id
  for id in "$@"; do
    if desktop_id_exists "$id"; then
      printf '%s\n' "$id"
      return 0
    fi
  done
  return 1
}

log "Default browser and mail"
if id="$(first_existing_desktop brave-browser.desktop com.brave.Browser.desktop)"; then
  xdg-settings set default-web-browser "$id" || true
  xdg-mime default "$id" x-scheme-handler/http || true
  xdg-mime default "$id" x-scheme-handler/https || true
  xdg-mime default "$id" text/html || true
else
  warn "Brave not installed; default browser unchanged"
fi
if id="$(first_existing_desktop thunderbird.desktop org.mozilla.Thunderbird.desktop)"; then
  xdg-mime default "$id" x-scheme-handler/mailto || true
fi
if id="$(first_existing_desktop vlc.desktop)"; then
  for mime in video/mp4 video/x-matroska video/x-msvideo video/webm; do
    xdg-mime default "$id" "$mime" || true
  done
fi
if id="$(first_existing_desktop gdebi.desktop)"; then
  python3 - "$id" <<'PY' || true
from pathlib import Path
import sys
app = sys.argv[1]
home = Path.home()
files = [
    home/".config/mimeapps.list",
    home/".config/gnome-mimeapps.list",
    home/".local/share/applications/mimeapps.list",
    home/".local/share/applications/defaults.list",
]
mimes = ("application/vnd.debian.binary-package", "application/x-deb")
for f in files:
    f.parent.mkdir(parents=True, exist_ok=True)
    text = f.read_text() if f.is_file() else ""
    lines = [ln for ln in text.splitlines() if not ln.startswith(mimes)]
    if "[Default Applications]" not in "\n".join(lines):
        lines.append("[Default Applications]")
    out = []
    for ln in lines:
        out.append(ln)
        if ln.strip() == "[Default Applications]":
            for mime in mimes:
                out.append(f"{mime}={app}")
    f.write_text("\n".join(out) + "\n")
print("deb handler", app)
PY
  xdg-mime default "$id" application/vnd.debian.binary-package || true
  xdg-mime default "$id" application/x-deb || true
fi
if id="$(first_existing_desktop org.gnome.Software.desktop gnome-software.desktop)"; then
  for mime in application/x-rpm application/x-redhat-package-manager; do
    xdg-mime default "$id" "$mime" || true
  done
fi
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
# ---------------------------------------------------------------------------
# AppImage launchers
# One helper does it all. Clicking an AppImage runs it. The installer runs it
# with --no-run on AppImages already in Downloads or ~/Applications.
# ---------------------------------------------------------------------------
put_file "$HOME/.local/bin/open-appimage" <<'EOF'
#!/usr/bin/env bash
# open-appimage [--no-run] FILE
# Moves an AppImage to ~/Applications, makes it executable, links it under
# AppFiles, and adds a Show Apps launcher with the app's own icon. Then it
# starts the app. The installer passes --no-run for ones already downloaded.
run=1
if [[ "${1:-}" == "--no-run" ]]; then
  run=0
  shift
fi
f="${1:-}"
[[ -n "$f" && -f "$f" && ! -L "$f" ]] || exit 1
base="$(basename "$f")"
case "${base,,}" in
  *.appimage) ;;
  *)
    zenity --error --text="Not an AppImage: $base" 2>/dev/null || echo "Not an AppImage: $base" >&2
    exit 1
    ;;
esac
name="${base%.[Aa]pp[Ii]mage}"
apps="$HOME/.local/share/applications"
desk="$apps/human-linux-appimage-${name}.desktop"
dest="$HOME/Applications/$base"
# A rerun of the installer leaves an AppImage that is already set up alone.
if [[ "$run" == 0 && -f "$desk" && "$f" -ef "$dest" ]]; then
  echo "    up to date $base"
  exit 0
fi
mkdir -p "$HOME/Applications" "$HOME/.local/share/icons" "$HOME/Documents/AppFiles/appimages" "$apps"
[[ "$f" -ef "$dest" ]] || mv "$f" "$dest"
chmod +x "$dest" || true
ln -sfn "$dest" "$HOME/Documents/AppFiles/appimages/$base"
cat > "$desk" <<DESK
[Desktop Entry]
Name=$name
Exec="$dest"
Icon=application-x-executable
Terminal=false
Type=Application
Categories=Utility;
StartupNotify=true
X-ReadyLinux=true
DESK
chmod +x "$desk" || true
gio set "$desk" metadata::trusted true 2>/dev/null || true
# Extract in a private folder. The icon is .DirIcon, or the first image inside.
# A link that points outside the extracted tree is ignored.
work="$(mktemp -d)"
(
  cd "$work" || exit 0
  "$dest" --appimage-extract >/dev/null 2>&1 || true
  found=""
  [[ -e squashfs-root/.DirIcon ]] && found="$(readlink -f squashfs-root/.DirIcon)"
  if [[ "$found" != "$work"/* || ! -s "$found" ]]; then
    found="$(find squashfs-root -type f \( -iname '*.png' -o -iname '*.svg' \) 2>/dev/null | head -n1)"
  fi
  if [[ -s "$found" ]]; then
    case "${found,,}" in
      *.svg) icon="$HOME/.local/share/icons/${name}.svg" ;;
      *)     icon="$HOME/.local/share/icons/${name}.png" ;;
    esac
    cp -f "$found" "$icon"
    sed -i "s|^Icon=.*|Icon=$icon|" "$desk"
  fi
)
rm -rf "$work"
update-desktop-database "$apps" 2>/dev/null || true
echo "    integrated $base"
if [[ "$run" == 1 ]]; then
  exec "$dest"
fi
EOF
chmod +x "$HOME/.local/bin/open-appimage"
put_file "$HOME/.local/share/applications/open-appimage.desktop" <<EOF
[Desktop Entry]
Name=Install AppImage
Exec=$HOME/.local/bin/open-appimage %f
Terminal=false
Type=Application
MimeType=application/vnd.appimage;application/x-iso9660-appimage;
NoDisplay=true
X-ReadyLinux=true
EOF
mkdir -p "$HOME/.local/share/mime/packages"
put_file "$HOME/.local/share/mime/packages/appimage.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/vnd.appimage">
    <comment>AppImage</comment>
    <glob pattern="*.AppImage"/>
    <glob pattern="*.appimage"/>
  </mime-type>
</mime-info>
EOF
update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
xdg-mime default open-appimage.desktop application/vnd.appimage || true
xdg-mime default open-appimage.desktop application/x-iso9660-appimage || true
log "AppImage launchers"
shopt -s nullglob
for d in "$HOME/Downloads"/*.AppImage "$HOME/Downloads"/*.appimage \
         "$HOME/Applications"/*.AppImage "$HOME/Applications"/*.appimage; do
  "$HOME/.local/bin/open-appimage" --no-run "$d" || warn "Could not set up $(basename "$d")"
done
shopt -u nullglob
# An executable AppImage is launched by Files and skips this handler.
# Leave Downloads copies non-executable so a click installs them.
shopt -s nullglob
for d in "$HOME/Downloads"/*.AppImage "$HOME/Downloads"/*.appimage; do
  chmod a-x "$d" 2>/dev/null || true
done
shopt -u nullglob
if id="$(first_existing_desktop gnome-disk-image-writer.desktop org.gnome.DiskUtility.desktop)"; then
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
  put_file "$HOME/.local/bin/open-iso" <<'EOF'
#!/usr/bin/env bash
iso="${1:-}"
[[ -n "$iso" && -f "$iso" ]] || exit 1
real="$(readlink -f "$iso")"
# Files mounts the ISO on click. Disk Image Writer errors if it is mounted.
while read -r loop back; do
  [[ "$back" == "$real" ]] || continue
  udisksctl unmount -b "$loop" >/dev/null 2>&1 || umount -l "$loop" >/dev/null 2>&1 || true
  udisksctl loop-delete -b "$loop" >/dev/null 2>&1 || losetup -d "$loop" >/dev/null 2>&1 || true
done < <(losetup -lnO NAME,BACK-FILE 2>/dev/null || true)
# A restore fails if the USB stick is still mounted. Unmount removable disks only.
while read -r dev rm; do
  [[ "$rm" == "1" ]] || continue
  while read -r part mp; do
    [[ -n "$mp" ]] || continue
    udisksctl unmount -b "$part" >/dev/null 2>&1 || umount -l "$part" >/dev/null 2>&1 || true
  done < <(lsblk -pnr -o PATH,MOUNTPOINT "$dev")
done < <(lsblk -dnr -o PATH,RM)
if command -v gnome-disk-image-writer >/dev/null; then
  exec gnome-disk-image-writer "$iso"
fi
exec gnome-disks
EOF
  chmod +x "$HOME/.local/bin/open-iso"
  put_file "$HOME/.local/share/applications/open-iso.desktop" <<EOF
[Desktop Entry]
Name=Write ISO to USB
Exec=$HOME/.local/bin/open-iso %f
Terminal=false
Type=Application
MimeType=application/x-cd-image;application/x-iso9660-image;application/vnd.efi.iso;application/x-raw-disk-image;
NoDisplay=true
X-ReadyLinux=true
EOF
  for mime in application/x-cd-image application/x-iso9660-image application/vnd.efi.iso application/x-raw-disk-image; do
    xdg-mime default open-iso.desktop "$mime" || true
  done
fi

# ---------------------------------------------------------------------------
# Dock, scale, wallpaper, editor, terminal
# Desktop branch:
#   cosmic   COSMIC favorites file and Files sidebar
#   cinnamon Cinnamon panel pins
#   mate     MATE panel pins, 40px
#   xfce     Whisker favorites, left-side pins, tray on the right. No rewrite.
#   zorin    GNOME pins only. Panel layout is left alone.
#   kde      Places file only. Panel is left alone.
#   *        GNOME pins. Fedora enables Dash to Dock at 40px.
# Scale is 125% on a laptop or 1080p, 100% otherwise.
# Wallpaper is set on GNOME, MATE, and Xfce. Already-ours is left alone.
# ---------------------------------------------------------------------------
log "Session settings"
de="$(desktop_session | tr '[:upper:]' '[:lower:]')"

pin_gnome() {
  need_cmd gsettings || return 0
  need_cmd python3 || return 0
  local schema="$1"
  local files="$2"
  local editor="$3"
  gsettings writable "$schema" favorite-apps >/dev/null 2>&1 || return 0
  gsettings list-keys "$schema" 2>/dev/null | grep -qx favorite-apps || return 0
  python3 - "$schema" "$files" "$editor" <<'PY'
import ast, subprocess, sys
schema, files, editor = sys.argv[1:]
wanted = [
  "brave-browser.desktop",
  "google-chrome.desktop",
  editor,
  files,
  "org.gnome.Calculator.desktop",
  "org.gnome.Terminal.desktop",
]
# Browsers and mail by real filename. Zorin may not use firefox.desktop.
import pathlib
def first_named(word):
    for folder in (
        pathlib.Path("/usr/share/applications"),
        pathlib.Path("/var/lib/snapd/desktop/applications"),
        pathlib.Path.home()/".local/share/applications",
    ):
        if not folder.is_dir():
            continue
        for f in sorted(folder.glob("*.desktop")):
            if word in f.name.lower():
                return f.name
    return None
browser = first_named("firefox")
if browser:
    wanted.insert(2, browser)
mail = first_named("thunderbird")
if mail:
    wanted.insert(3, mail)
wanted.insert(4, "org.keepassxc.KeePassXC.desktop")
wanted.insert(5, "libreoffice-writer.desktop")
raw = subprocess.check_output(["gsettings", "get", schema, "favorite-apps"], text=True)
try:
    cur = ast.literal_eval(raw.strip())
except Exception:
    cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted]
out = []
for x in wanted:
    if x in ("", "None"):
        continue
    p1 = pathlib.Path("/usr/share/applications") / x
    p2 = pathlib.Path.home() / ".local/share/applications" / x
    p3 = pathlib.Path("/var/lib/snapd/desktop/applications") / x
    if p1.is_file() or p2.is_file() or p3.is_file():
        out.append(x)
out += [x for x in rest if x not in out]
repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
subprocess.check_call(["gsettings", "set", schema, "favorite-apps", repr_out])
print("pinned", repr_out)
PY
  # AppImages belong in Show Apps, not on the dock.
  python3 - "$schema" <<'PY' || true
import ast, subprocess, sys
schema = sys.argv[1]
raw = subprocess.check_output(["gsettings", "get", schema, "favorite-apps"], text=True)
try:
    cur = ast.literal_eval(raw.strip())
except Exception:
    cur = []
if isinstance(cur, list):
    out = [x for x in cur if "appimage" not in x.lower()]
    if out != cur:
        repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
        subprocess.check_call(["gsettings", "set", schema, "favorite-apps", repr_out])
        print("unpinned appimages", repr_out)
PY
}

case "$de" in
  *cosmic*)
    log "COSMIC dock and Files sidebar"
    fav="$HOME/.config/cosmic/com.system76.CosmicAppList/v1/favorites"
    mkdir -p "$(dirname "$fav")"
    python3 - "$fav" <<'PY' || true
import json, os, sys
from pathlib import Path
path = sys.argv[1]
candidates = [
  "brave-browser", "com.brave.Browser",
  "google-chrome", "com.google.Chrome",
  "firefox", "thunderbird", "org.mozilla.Thunderbird",
  "org.keepassxc.KeePassXC", "libreoffice-writer",
  "com.system76.CosmicEdit", "org.gnome.TextEditor",
  "com.system76.CosmicFiles", "org.gnome.Nautilus",
  "org.gnome.Calculator",
  "com.system76.CosmicStore",
  "com.system76.CosmicTerm",
  "com.system76.CosmicSettings",
]
def exists(appid):
    return Path(f"/usr/share/applications/{appid}.desktop").is_file() or Path.home().joinpath(f".local/share/applications/{appid}.desktop").is_file()
wanted = []
seen = set()
for appid in candidates:
    if appid in seen or not exists(appid):
        continue
    wanted.append(appid)
    seen.add(appid)
cur = []
if os.path.exists(path):
    try:
        cur = json.load(open(path))
    except Exception:
        cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted]
json.dump(wanted + rest, open(path, "w"), indent=4)
print("cosmic dock", wanted)
PY
    files_fav="$HOME/.config/cosmic/com.system76.CosmicFiles/v1/favorites"
    mkdir -p "$(dirname "$files_fav")"
    if [[ ! -f "$files_fav" ]]; then
      put_file "$files_fav" <<EOF
[
    Home,
    Documents,
    Downloads,
    Pictures,
    Videos,
    Path("$HOME/Media"),
    Path("$HOME/Documents/AppFiles"),
    Path("/"),
]
EOF
    else
      grep -q "$HOME/Media" "$files_fav" || sed -i "s/\]/    Path(\"$HOME\/Media\"),\n]/" "$files_fav"
      grep -q "$HOME/Documents/AppFiles" "$files_fav" || sed -i "s/\]/    Path(\"$HOME\/Documents\/AppFiles\"),\n]/" "$files_fav"
    fi
    ;;
  *cinnamon*)
    log "Cinnamon panel pins"
    python3 - <<'PY' || true
import json
from pathlib import Path
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "org.gnome.TextEditor.desktop", "gedit.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["nemo.desktop", "org.gnome.Calculator.desktop", "org.gnome.Terminal.desktop"]
roots = [
  Path.home() / ".config/cinnamon/spices/grouped-window-list@cinnamon.org",
  Path.home() / ".cinnamon/configs/grouped-window-list@cinnamon.org",
]
files = []
for root in roots:
    if root.is_dir():
        files.extend(root.glob("*.json"))
if not files:
    print("no cinnamon panel config")
else:
    for f in files:
        try:
            data = json.loads(f.read_text())
        except Exception:
            continue
        pin = data.get("pinned-apps")
        cur = []
        if isinstance(pin, dict):
            cur = pin.get("value") or pin.get("default") or []
            pin["value"] = wanted + [x for x in cur if x not in wanted]
        elif isinstance(pin, list):
            data["pinned-apps"] = wanted + [x for x in pin if x not in wanted]
        else:
            data["pinned-apps"] = {"value": wanted}
        f.write_text(json.dumps(data, indent=4))
        print("cinnamon panel", f)
PY
    # The running panel keeps the old list until it is reloaded.
    cinnamon --replace >/dev/null 2>&1 &
    ;;
  *mate*)
    log "MATE menu pins"
    if gsettings list-schemas | grep -qx 'com.linuxmint.mintmenu.plugins.applications'; then
      python3 - <<'PY' || true
import ast, subprocess
from pathlib import Path
schema = "com.linuxmint.mintmenu.plugins.applications"
key = "favorite-apps-list"
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "pluma.desktop", "org.gnome.TextEditor.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["caja.desktop", "org.gnome.Calculator.desktop", "mate-terminal.desktop"]
raw = subprocess.check_output(["gsettings", "get", schema, key], text=True).strip()
try:
    cur = ast.literal_eval(raw)
except Exception:
    cur = []
if not isinstance(cur, list):
    cur = []
rest = [x for x in cur if x not in wanted and x not in ("org.gnome.Nautilus.desktop", "nemo.desktop")]
out = wanted + rest
repr_out = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in out) + "]"
subprocess.check_call(["gsettings", "set", schema, key, repr_out])
print("mate pins", repr_out)
PY
    fi
    log "MATE panel launchers"
    python3 - <<'PY' || true
import ast, subprocess
from pathlib import Path
wanted = [
  "brave-browser.desktop", "google-chrome.desktop", "firefox.desktop",
  "thunderbird.desktop", "org.keepassxc.KeePassXC.desktop",
  "libreoffice-writer.desktop",
]
for editor in ("xed.desktop", "pluma.desktop", "org.gnome.TextEditor.desktop"):
    if Path("/usr/share/applications", editor).is_file():
        wanted.append(editor)
        break
wanted += ["caja.desktop", "org.gnome.Calculator.desktop", "mate-terminal.desktop"]
def run(args):
    return subprocess.check_output(args, text=True).strip()
try:
    ids = ast.literal_eval(run(["gsettings", "get", "org.mate.panel", "object-id-list"]))
except Exception:
    print("no mate panel")
    raise SystemExit
if not isinstance(ids, list):
    ids = []
existing = set()
for oid in ids:
    loc = subprocess.run(["gsettings", "get", f"org.mate.panel.object:/org/mate/panel/objects/{oid}/", "launcher-location"], text=True, capture_output=True)
    if loc.returncode == 0:
        existing.add(loc.stdout.strip().strip("'"))
pos = 20
added = []
for name in wanted:
    desktop = f"/usr/share/applications/{name}"
    if not Path(desktop).is_file() or desktop in existing or name in existing:
        continue
    oid = f"readylinux-{name.replace('.desktop','')}"
    path = f"org.mate.panel.object:/org/mate/panel/objects/{oid}/"
    subprocess.check_call(["gsettings", "set", path, "object-type", "launcher"])
    subprocess.check_call(["gsettings", "set", path, "launcher-location", desktop])
    subprocess.check_call(["gsettings", "set", path, "toplevel-id", "bottom"])
    subprocess.check_call(["gsettings", "set", path, "position", str(pos)])
    subprocess.check_call(["gsettings", "set", path, "locked", "true"])
    ids.append(oid)
    added.append(name)
    pos += 20
if added:
    repr_ids = "[" + ", ".join("'" + x.replace("'", "") + "'" for x in ids) + "]"
    subprocess.check_call(["gsettings", "set", "org.mate.panel", "object-id-list", repr_ids])
    print("mate panel", added)
else:
    print("mate panel unchanged")
PY
    # Mint's bottom bar is 24px. 40 matches the other desktops.
    tids="$(gsettings get org.mate.panel toplevel-id-list 2>/dev/null | tr -d "[],'" || true)"
    args=()
    for tid in ${tids:-bottom}; do
      args+=("org.mate.panel.toplevel:/org/mate/panel/toplevels/$tid/" size 40)
    done
    gset_once "${args[@]}"
    ;;
  *xfce*)
    log "Xfce Whisker favorites and left-side pins"
    # Skip apps already on the bar. Reset the list, do not append.
    # An expanding separator is what right-justifies the tray and clock.
    if command -v xfconf-query >/dev/null; then
      names=(brave-browser.desktop google-chrome.desktop firefox.desktop \
             thunderbird.desktop org.keepassxc.KeePassXC.desktop \
             libreoffice-writer.desktop xed.desktop org.gnome.TextEditor.desktop kolourpaint.desktop org.kde.kolourpaint.desktop \
             thunar.desktop org.gnome.Calculator.desktop xfce4-terminal.desktop)
      editor=""
      for e in /usr/share/applications/{xed,org.gnome.TextEditor,mousepad}*.desktop; do
        if [[ -f "$e" ]]; then editor="$(basename "$e")"; break; fi
      done
      [[ -n "$editor" ]] && names+=("$editor")
      args=(-c xfce4-panel -p /plugins/plugin-1/favorites -n)
      for n in "${names[@]}"; do
        [[ -f "/usr/share/applications/$n" ]] && args+=(-t string -s "$n")
      done
      xfconf-query "${args[@]}" || true
      ids="$(xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids 2>/dev/null || true)"
      nums="$(echo "$ids" | grep -E '^[0-9]+$' | awk '!seen[$0]++' || true)"
      have=""
      for n in $nums; do
        item="$(xfconf-query -c xfce4-panel -p /plugins/plugin-$n/items 2>/dev/null | grep -E '\.desktop$' | head -n1 || true)"
        [[ -n "$item" ]] && have="$have $item"
      done
      next=40
      new=()
      for name in "${names[@]}"; do
        src="/usr/share/applications/$name"
        [[ -f "$src" ]] || continue
        [[ "$have" == *" $name"* ]] && continue
        while echo "$nums" | grep -qx "$next"; do next=$((next + 1)); done
        mkdir -p "$HOME/.config/xfce4/panel/launcher-$next"
        cp -f "$src" "$HOME/.config/xfce4/panel/launcher-$next/$name"
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next" -n -t string -s launcher || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next/items" -r 2>/dev/null || true
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$next/items" -n -t string -s "$name" || true
        new+=("$next")
        nums="$nums"$'\n'"$next"
        next=$((next + 1))
      done
      left=()
      system=()
      sep=""
      seen_items=" "
      for n in $nums; do
        [[ " ${new[*]} " == *" $n "* ]] && continue
        kind="$(xfconf-query -c xfce4-panel -p /plugins/plugin-$n 2>/dev/null || true)"
        item="$(xfconf-query -c xfce4-panel -p /plugins/plugin-$n/items 2>/dev/null | grep -E '\.desktop$' | head -n1 || true)"
        if [[ -n "$item" && "$seen_items" == *" $item "* ]]; then
          continue
        fi
        [[ -n "$item" ]] && seen_items="$seen_items$item "
        if [[ "$item" == *xed* || "$item" == *TextEditor* || "$item" == *mousepad* || "$item" == *text-editor* ]]; then
          left+=("$n")
          continue
        fi
        case "$kind" in
          systray|notification-plugin|xapp-status-plugin|power-manager-plugin|pulseaudio|clock)
            xfconf-query -c xfce4-panel -p "/plugins/plugin-$n/items" -r 2>/dev/null || true
            system+=("$n")
            ;;
          separator)
            [[ -z "$sep" ]] && sep="$n"
            ;;
          *)
            left+=("$n")
            ;;
        esac
      done
      if [[ -z "$sep" ]]; then
        sep="$next"
        xfconf-query -c xfce4-panel -p "/plugins/plugin-$sep" -n -t string -s separator || true
      fi
      xfconf-query -c xfce4-panel -p "/plugins/plugin-$sep/expand" -n -t bool -s true || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -r || true
      args=(-c xfce4-panel -p /panels/panel-1/plugin-ids -n)
      for n in "${left[@]}" "${new[@]}" "$sep" "${system[@]}"; do
        [[ -n "$n" ]] && args+=(-t int -s "$n")
      done
      xfconf-query "${args[@]}" || true
      xfce4-panel -r || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/size -n -t int -s 40 || true
      xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size -n -t int -s 40 || true
    fi
    sudo apt-get install -y wmctrl xdotool || true
    # Xed remembers a maximized 1920x1003 window. 0 is not maximized.
    if gsettings list-schemas | grep -qx 'org.x.editor.state.window'; then
      gsettings set org.x.editor.state.window size "(1100, 700)" || true
      gsettings set org.x.editor.state.window state 0 || true
    fi
    if command -v xfconf-query >/dev/null; then
      xfconf-query -c thunar -p /last-window-width -n -t int -s 1100 2>/dev/null || true
      xfconf-query -c thunar -p /last-window-height -n -t int -s 700 2>/dev/null || true
      xfconf-query -c thunar -p /last-window-maximized -n -t bool -s false 2>/dev/null || true
    fi
    # Thunar does not remember position. The menu launcher moves it after open.
    if command -v wmctrl >/dev/null && command -v xdotool >/dev/null; then
      mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
      put_file "$HOME/.local/bin/thunar-place" <<'EOF'
#!/usr/bin/env bash
/usr/bin/thunar "$@" &
sleep 0.6
hex="$(wmctrl -l | grep -i thunar | awk '{print $1; exit}')"
[[ -n "${hex:-}" ]] || exit 0
dec=$((hex))
wmctrl -i -r "$hex" -b remove,maximized_vert,maximized_horz
xdotool windowmove "$dec" 40 40
xdotool windowsize "$dec" 1100 700
EOF
      chmod +x "$HOME/.local/bin/thunar-place"
      put_file "$HOME/.local/share/applications/thunar.desktop" <<EOF
[Desktop Entry]
Name=Thunar
Exec=$HOME/.local/bin/thunar-place %F
Icon=thunar
Terminal=false
Type=Application
Categories=System;FileManager;
MimeType=inode/directory;
EOF
    fi
    ;;
  *zorin*)
    log "Zorin pins only. Panel layout is left as Zorin set it."
    pin_gnome org.gnome.shell org.gnome.Nautilus.desktop org.gnome.TextEditor.desktop || true
    ;;
  *kde*|*plasma*)
    log "KDE places. Panel pins are not the Ubuntu dock, so they are left as they are."
    xbel="$HOME/.local/share/user-places.xbel"
    mkdir -p "$HOME/.local/share"
    if [[ ! -f "$xbel" ]]; then
      printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<xbel version="1.0">' '</xbel>' > "$xbel"
    fi
    for pair in "$HOME/Media|Media" "$HOME/Documents/AppFiles|AppFiles"; do
      uri="file://${pair%%|*}"
      label="${pair##*|}"
      grep -qF "$uri" "$xbel" || sed -i "s#</xbel># <bookmark href=\"$uri\"><title>$label</title></bookmark>\n</xbel>#" "$xbel"
    done
    ;;
  *)
    pin_gnome org.gnome.shell org.gnome.Nautilus.desktop org.gnome.TextEditor.desktop || true
    if gsettings list-schemas | grep -q 'org.gnome.shell.extensions.dash-to-dock'; then
      gnome-extensions enable dash-to-dock@micxgx.gmail.com 2>/dev/null || true
      # Only if the dock is still where the distro put it.
      gset_once org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'" \
                org.gnome.shell.extensions.dash-to-dock extend-height false \
                org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 40
    fi
    ;;
esac

if gsettings list-keys org.gnome.settings-daemon.plugins.power 2>/dev/null | grep -q lid-close-ac-action; then
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'nothing' || true
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'suspend' || true
fi

# Files remembers a maximized window. Open it at a normal size.
if gsettings list-schemas | grep -qx 'org.gnome.nautilus.window-state'; then
  gsettings set org.gnome.nautilus.window-state maximized false || true
  gsettings set org.gnome.nautilus.window-state initial-size '(1100, 700)' || true
fi
# Preferences below are set once. A value you changed yourself is kept.
gset_once org.gnome.TextEditor style-scheme "'classic'" \
          org.gnome.TextEditor use-system-font false \
          org.gnome.TextEditor custom-font "'Monospace 12'" \
          org.gnome.gedit.preferences.editor scheme "'classic'" \
          org.gnome.gedit.preferences.editor use-default-font false \
          org.gnome.gedit.preferences.editor editor-font "'Monospace 12'"
python3 - <<'PY' || true
from pathlib import Path
try:
    from gi.repository import GLib
except Exception:
    raise SystemExit(0)
path = Path.home() / ".local/share/org.gnome.TextEditor/session.gvariant"
if not path.is_file():
    raise SystemExit(0)
data = GLib.Bytes.new(path.read_bytes())
variant = GLib.Variant.new_from_bytes(GLib.VariantType.new("a{sv}"), data, False)
items = []
for i in range(variant.n_children()):
    entry = variant.get_child_value(i)
    key = entry.get_child_value(0).get_string()
    if key == "default-window-size":
        items.append((key, GLib.Variant("(uu)", (1100, 700))))
    else:
        items.append((key, entry.get_child_value(1).get_variant()))
new = GLib.Variant("a{sv}", items)
path.write_bytes(bytes(new.get_data_as_bytes().get_data()))
print("text editor window 1100x700")
PY
gset_once org.x.editor.preferences.editor use-default-font false \
          org.x.editor.preferences.editor editor-font "'Monospace 12'"

# Terminal frame is 110x34 on the distros we support. Colors are not touched.
# Newer Ubuntu uses Ptyxis. Zorin and Mint use GNOME Terminal.
gset_once org.gnome.Ptyxis default-columns 110 \
          org.gnome.Ptyxis default-rows 34 \
          org.gnome.Ptyxis use-system-font false \
          org.gnome.Ptyxis font-name "'Monospace 10'"
if gsettings list-schemas | grep -qx 'org.gnome.Terminal.Legacy.Settings' && command -v gnome-terminal >/dev/null; then
  uids="$(dconf list /org/gnome/terminal/legacy/profiles:/ 2>/dev/null | tr -d ':/' || true)"
  default="$(gsettings get org.gnome.Terminal.Legacy.Settings default 2>/dev/null | tr -d "'" || true)"
  [[ -n "$default" && " $uids " != *" $default "* ]] && uids="$uids $default"
  args=()
  for uid in $uids; do
    path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uid/"
    args+=("$path" default-size-columns 110 "$path" default-size-rows 34
           "$path" use-system-font false "$path" font "'Monospace 10'")
  done
  if ((${#args[@]})); then
    gset_once "${args[@]}"
  else
    echo "    gnome-terminal has no profile yet. Size applies after the next run."
  fi
  # Older kits replaced the Terminal launcher to force --geometry. The profile
  # size does the same job, so put the system launcher back.
  old_term="$HOME/.local/share/applications/org.gnome.Terminal.desktop"
  if [[ -f "$old_term" ]] && grep -qx 'Exec=gnome-terminal --geometry=110x34' "$old_term"; then
    rm -f "$old_term"
    echo "    removed the old forced-size Terminal launcher"
  fi
fi
# Xfce Terminal ignores the GNOME geometry. Each key is added only if missing.
if [[ -d /usr/share/xfce4/terminal || -f /usr/bin/xfce4-terminal ]]; then
  mkdir -p "$HOME/.config/xfce4/terminal"
  termrc="$HOME/.config/xfce4/terminal/terminalrc"
  touch "$termrc"
  grep -q '^\[Configuration\]' "$termrc" || printf '\n[Configuration]\n' >> "$termrc"
  for kv in "MiscDefaultGeometry=120x36" "FontName=Monospace 10"; do
    grep -q "^${kv%%=*}=" "$termrc" || printf '%s\n' "$kv" >> "$termrc"
  done
fi

# 125% on a laptop or a 1080p-class screen. A desktop at 1440p or 4K stays at 100%.
primary_w="$(xrandr 2>/dev/null | awk '/ connected/{print $3; exit}' | cut -dx -f1)"
if [[ -d /sys/class/power_supply ]] && compgen -G /sys/class/power_supply/BAT* >/dev/null; then
  SCALE="1.25"
elif [[ -n "${primary_w:-}" && "$primary_w" -le 1920 ]]; then
  SCALE="1.25"
else
  SCALE="1.0"
fi
log "Screen scale $SCALE"
gset_once org.gnome.desktop.interface text-scaling-factor "$SCALE" \
          org.cinnamon.desktop.interface text-scaling-factor "$SCALE" \
          org.cinnamon active-display-scale "$SCALE"
# MATE has no 125% display scale. 120 DPI is the same size change.
if [[ "$SCALE" == "1.25" ]]; then
  gset_once org.mate.font-rendering dpi 120.0
fi
# Xfce uses DPI, not the GNOME scale key. 120 is the 125% size.
# Set only when no DPI was chosen yet.
if [[ "$SCALE" == "1.25" ]] && command -v xfconf-query >/dev/null \
   && ! xfconf-query -c xsettings -p /Xft/DPI >/dev/null 2>&1; then
  xfconf-query -c xsettings -p /Xft/DPI -n -t int -s 120 2>/dev/null || true
fi
if [[ "$SCALE" == "1.25" && -f "$HOME/.config/cinnamon-monitors.xml" ]]; then
  sed -i 's/scale="0.75"/scale="1.25"/g; s/<scale>0.75<\/scale>/<scale>1.25<\/scale>/g' \
    "$HOME/.config/cinnamon-monitors.xml" || true
fi

if [[ -n "$WALLPAPER_URL" ]]; then
  mkdir -p "$HOME/.local/share/backgrounds"
  wall="$HOME/.local/share/backgrounds/human-linux-wallpaper.jpg"
  if gsettings list-schemas | grep -qx 'org.mate.background'; then
    current="$(gsettings get org.mate.background picture-filename 2>/dev/null || echo '')"
    if [[ "$current" == *"/usr/share/backgrounds/"* || "$current" == "''" ]]; then
      if [[ -s "$wall" ]] || fetch_image "$WALLPAPER_URL" "$wall"; then
        gsettings set org.mate.background picture-filename "$wall" || true
        gsettings set org.mate.background picture-options 'zoom' || true
      else
        warn "Wallpaper download failed"
      fi
    else
      log "Wallpaper already chosen. Skipped."
    fi
  else
    current="$(gsettings get org.gnome.desktop.background picture-uri 2>/dev/null || echo '')"
    dark="$(gsettings get org.gnome.desktop.background picture-uri-dark 2>/dev/null || echo '')"
    if [[ "$current" == *"human-linux-wallpaper.jpg"* && "$dark" == *"human-linux-wallpaper.jpg"* ]]; then
      log "Wallpaper already set."
    elif [[ -s "$wall" ]] || fetch_image "$WALLPAPER_URL" "$wall"; then
      gsettings set org.gnome.desktop.background picture-uri "file://$wall" || true
      gsettings set org.gnome.desktop.background picture-uri-dark "file://$wall" || true
      gsettings set org.gnome.desktop.background picture-options 'zoom' || true
    else
      warn "Wallpaper download failed"
    fi
  fi
else
  log "Wallpaper URL blank. Skipped."
fi
# Xfce wallpaper is per monitor. The live laptop panel is monitoreDP-1.
# last-image alone does not change the picture while cycling is on.
if [[ -n "$WALLPAPER_URL" ]] && command -v xfconf-query >/dev/null && [[ "$de" == *xfce* ]]; then
  mkdir -p "$HOME/.local/share/backgrounds"
  wall="$HOME/.local/share/backgrounds/human-linux-wallpaper.jpg"
  if [[ -s "$wall" ]] || fetch_image "$WALLPAPER_URL" "$wall"; then
    for prop in \
      /backdrop/screen0/monitoreDP-1/workspace0/last-image \
      /backdrop/screen0/monitoreDP-1/workspace0/image-path \
      /backdrop/screen0/monitor0/image-path \
      /backdrop/screen0/monitor0/last-single-image
    do
      xfconf-query -c xfce4-desktop -p "$prop" -n -t string -s "$wall" 2>/dev/null || true
    done
    xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitoreDP-1/workspace0/backdrop-cycle-enable -n -t bool -s false 2>/dev/null || true
  fi
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# Click a .sh in Files: Run or Edit, instead of opening the text editor.
log "Script launcher"
put_file "$HOME/.local/bin/sh-launcher" <<'EOF'
#!/usr/bin/env bash
f="${1:-}"
[[ -n "$f" && -f "$f" ]] || { zenity --error --text="No script given."; exit 1; }
zenity --question --width=420 --title="Script" \
  --ok-label="Run" --cancel-label="Edit" \
  --text="File: $f

Run starts this script.
Edit opens it in the text editor." || {
  if command -v gnome-text-editor >/dev/null; then exec gnome-text-editor "$f"
  elif command -v gedit >/dev/null; then exec gedit "$f"
  elif command -v xed >/dev/null; then exec xed "$f"
  elif command -v pluma >/dev/null; then exec pluma "$f"
  elif command -v mousepad >/dev/null; then exec mousepad "$f"
  else zenity --error --text="No text editor found."
  fi
  exit 0
}
chmod +x "$f" || true
if command -v gnome-terminal >/dev/null; then
  gnome-terminal -- bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
elif command -v kgx >/dev/null; then
  kgx -- bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
elif command -v x-terminal-emulator >/dev/null; then
  x-terminal-emulator -e bash -c "bash \"$f\"; echo; read -r -p 'Press Enter to close.'"
else
  zenity --error --text="No terminal program found."
fi
EOF
chmod +x "$HOME/.local/bin/sh-launcher"
put_file "$HOME/.local/share/applications/sh-launcher.desktop" <<EOF
[Desktop Entry]
Name=Script launcher
Exec=$HOME/.local/bin/sh-launcher %f
Terminal=false
Type=Application
MimeType=text/x-shellscript;application/x-shellscript;
NoDisplay=true
X-ReadyLinux=true
EOF
xdg-mime default sh-launcher.desktop text/x-shellscript || true
xdg-mime default sh-launcher.desktop application/x-shellscript || true
# Nemo asks Run or Display before the default app. Launch skips that and opens ours.
if gsettings writable org.nemo.preferences executable-text-activation >/dev/null 2>&1; then
  gsettings set org.nemo.preferences executable-text-activation 'launch' || true
fi

# Clickable launchers. Files will not run a .sh; these .desktop files do.
if [[ -f "$0" ]]; then
  kit="$HOME/.local/share/human-linux"
  mkdir -p "$kit" "$HOME/.local/share/applications"
  cp -f "$0" "$kit/install.sh"
  chmod +x "$kit/install.sh"
  if [[ -f "$(dirname "$0")/uninstall.sh" ]]; then
    cp -f "$(dirname "$0")/uninstall.sh" "$kit/uninstall.sh"
    chmod +x "$kit/uninstall.sh"
  fi
  put_file "$HOME/.local/share/applications/human-linux-install.desktop" <<EOF
[Desktop Entry]
Name=ReadyLinux install
Comment=Preview, confirm, then run the install
Exec=$kit/install.sh
Terminal=false
Type=Application
Icon=system-software-install
Categories=Utility;
EOF
  put_file "$HOME/.local/share/applications/human-linux-uninstall.desktop" <<EOF
[Desktop Entry]
Name=ReadyLinux uninstall
Comment=Preview, confirm, then remove kit files
Exec=$kit/uninstall.sh
Terminal=false
Type=Application
Icon=user-trash
Categories=Utility;
EOF
  chmod +x "$HOME/.local/share/applications/human-linux-install.desktop" \
           "$HOME/.local/share/applications/human-linux-uninstall.desktop" || true
  gio set "$HOME/.local/share/applications/human-linux-install.desktop" metadata::trusted true 2>/dev/null || true
  gio set "$HOME/.local/share/applications/human-linux-uninstall.desktop" metadata::trusted true 2>/dev/null || true
fi

mkdir -p "$(dirname "$KIT_STAMP")"
printf '%s\n%s\n' "$KIT_VERSION" "$(date -Iseconds)" > "$KIT_STAMP"

log "Done."
if [[ -n "$KIT_PREV" && "$KIT_PREV" != "$KIT_VERSION" ]]; then
  echo "Updated ReadyLinux $KIT_PREV to $KIT_VERSION."
elif [[ -n "$KIT_PREV" ]]; then
  echo "ReadyLinux $KIT_VERSION was already installed. Rechecked."
fi
echo "Packages: ${#PKG_MISSING[@]} installed, ${#PKG_OUTDATED[@]} updated."
echo "Kit files: ${#KIT_NEW[@]} new, ${#KIT_UPDATED[@]} updated, $KIT_SAME already up to date."
echo "Plug a USB stick in. It should appear under ~/Media/Disks after Ubuntu mounts it."
echo "Show Apps: ReadyLinux install, and ReadyLinux uninstall."
echo "Log out and back in if Show Apps or the dock did not update."
echo "On Zorin, dock icons can show but not click until that logout."
echo "Lid-on-AC applies fully after the next reboot. logind was not restarted."
}

[[ -n "${READYLINUX_TEST:-}" ]] || main "$@"
