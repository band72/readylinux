#!/usr/bin/env bash
# ReadyLinux — uninstall
# Removes files and rules the install script created.
# Does not remove packages. Does not undo dock, scale, pins, or browser defaults.
if [[ ! -t 1 ]]; then
  zenity --question --width=420 --title="ReadyLinux uninstall" \
    --text="This removes the links, bookmarks, watcher, Find my file, Brax.me, the lid rule, the IPv4 preference, and the file associations for deb, rpm, AppImage, ISO, video, and scripts.\n\nPackages stay installed. A terminal will open for your password. Continue?" \
    || exit 0
  term="$(command -v gnome-terminal || command -v x-terminal-emulator || true)"
  [[ -n "$term" ]] || { zenity --error --text="No terminal found."; exit 1; }
  exec "$term" -- bash -c "\"$0\"; echo; read -r -p 'Press Enter to close.'"
fi
set -euo pipefail

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  warn "Run as your user, not root."
  exit 1
fi

log "Links and bookmarks"
find "$HOME/Media/Disks" -maxdepth 1 -type l -delete 2>/dev/null || true
rm -f "$HOME/Media/Phone"
find "$HOME/Documents/AppFiles" -maxdepth 2 -type l -delete 2>/dev/null || true
rm -rf "$HOME/Documents/AppFiles/appimages"
rm -rf "$HOME/Documents/AppFiles"
rmdir "$HOME/Media/Disks" "$HOME/Media" "$HOME/Videos/OBS" 2>/dev/null || true

for f in "$HOME/.config/gtk-3.0/bookmarks" "$HOME/.config/gtk-4.0/bookmarks"; do
  [[ -f "$f" ]] || continue
  grep -vE 'file://.+/Media |file://.+/AppFiles ' "$f" > "$f.tmp" || true
  mv "$f.tmp" "$f"
done
if [[ -f "$HOME/.local/share/user-places.xbel" ]]; then
  grep -vE 'file://.+/Media"|file://.+/AppFiles"' "$HOME/.local/share/user-places.xbel" > "$HOME/.local/share/user-places.xbel.tmp" || true
  mv "$HOME/.local/share/user-places.xbel.tmp" "$HOME/.local/share/user-places.xbel"
fi
rm -f "$HOME/.local/share/org.gnome.Ptyxis/palettes/kit-contrast.palette"

systemctl --user disable --now human-linux-usb-watch.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/human-linux-usb-watch.service" \
      "$HOME/.local/bin/human-linux-usb-watch" \
      "$HOME/.local/bin/where-is-my-file" \
      "$HOME/.local/bin/where-is-my-file-gui" \
      "$HOME/.local/share/applications/where-is-my-file.desktop" \
      "$HOME/.local/share/applications/brax-me.desktop" \
      "$HOME/.local/share/icons/brax-me.png" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/readylinux-find-my-file.svg" \
      "$HOME/.local/share/human-linux/version" \
      "$HOME/.local/share/backgrounds/human-linux-wallpaper.jpg"
# Undo AppImage integration. Remove the launcher and put the file back in Downloads.
shopt -s nullglob
for f in "$HOME/Applications"/*.AppImage "$HOME/Applications"/*.appimage \
         "$HOME/Documents"/*.AppImage "$HOME/Documents"/*.appimage; do
  base="$(basename "$f")"
  [[ -e "$HOME/Downloads/$base" ]] || mv "$f" "$HOME/Downloads/$base"
  echo "restored $base to Downloads"
done
for desk in "$HOME/.local/share/applications"/*.desktop; do
  if grep -qiE 'AppImage|appimagekit_|\.AppImage' "$desk" 2>/dev/null; then
    rm -f "$desk"
    echo "removed launcher $(basename "$desk")"
  fi
done
shopt -u nullglob
rm -f "$HOME/.local/share/applications"/human-linux-appimage-*.desktop \
      "$HOME/.local/bin/sh-launcher" \
      "$HOME/.local/bin/open-iso" \
      "$HOME/.local/bin/open-appimage" \
      "$HOME/.local/share/applications/sh-launcher.desktop" \
      "$HOME/.local/share/applications/open-iso.desktop" \
      "$HOME/.local/share/applications/open-appimage.desktop"
rm -f "$HOME/.local/share/applications/org.gnome.Terminal.desktop" \
      "$HOME/.local/bin/thunar-place" \
      "$HOME/.local/share/applications/thunar.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
log "File associations"
python3 - <<'PY' || true
from pathlib import Path
types = {
  "application/vnd.debian.binary-package", "application/x-deb",
  "application/x-rpm", "application/x-redhat-package-manager",
  "application/vnd.appimage", "application/x-iso9660-appimage",
  "application/x-cd-image", "application/x-iso9660-image",
  "application/vnd.efi.iso", "application/x-raw-disk-image",
  "video/mp4", "video/x-matroska", "video/x-msvideo", "video/webm",
  "text/x-shellscript", "application/x-shellscript",
}
for f in [Path.home()/".config/mimeapps.list", Path.home()/".local/share/applications/mimeapps.list"]:
    if not f.is_file():
        continue
    kept = []
    for line in f.read_text().splitlines():
        key = line.split("=", 1)[0].strip()
        if key in types:
            continue
        kept.append(line)
    f.write_text("\n".join(kept) + "\n")
    print("cleared", f)
PY
# GDebi stays installed, so the system default is still GDebi.
# Write the Archive Manager default into every user list Files reads.
python3 - <<'PY' || true
from pathlib import Path
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
    if "[Removed Associations]" not in "\n".join(lines):
        lines.append("[Removed Associations]")
    out = []
    for ln in lines:
        out.append(ln)
        if ln.strip() == "[Default Applications]":
            for mime in mimes:
                out.append(f"{mime}=org.gnome.FileRoller.desktop")
        if ln.strip() == "[Removed Associations]":
            for mime in mimes:
                out.append(f"{mime}=gdebi.desktop;")
    f.write_text("\n".join(out) + "\n")
    print("updated", f)
PY
nautilus -q 2>/dev/null || true
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
systemctl --user daemon-reload 2>/dev/null || true

log "Lid rule and IPv4 preference"
if gsettings list-keys org.gnome.settings-daemon.plugins.power 2>/dev/null | grep -q lid-close-ac-action; then
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-ac-action 'suspend' || true
  gsettings set org.gnome.settings-daemon.plugins.power lid-close-battery-action 'suspend' || true
fi
sudo rm -f /etc/systemd/logind.conf.d/human-linux-lid.conf
if [[ -f /etc/gai.conf ]]; then
  sudo sed -i '/human-linux-ipv4/d' /etc/gai.conf
fi

nautilus -q 2>/dev/null || true
# A launcher removal can move the AppImage out of Downloads.
# Put it back from Documents or Applications.
shopt -s nullglob
for f in "$HOME/Documents"/*.AppImage "$HOME/Documents"/*.appimage \
         "$HOME/Applications"/*.AppImage "$HOME/Applications"/*.appimage; do
  base="$(basename "$f")"
  [[ -e "$HOME/Downloads/$base" ]] && continue
  mv "$f" "$HOME/Downloads/$base"
  echo "restored $base to Downloads"
done
shopt -u nullglob
log "Uninstall done. Packages were left installed. Dock, scale, and pins were left as they are."
echo "Lid file is removed. It applies on the next reboot. logind was not restarted."
echo "IPv6 is preferred again."
