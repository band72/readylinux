#!/usr/bin/env bash
# Tests for install.sh helpers. Runs in a throwaway HOME, needs no sudo.
#   bash tests/test_install.sh
# Variables below are read inside check's eval strings.
# shellcheck disable=SC2034
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home"
# No display, so a zenity dialog fails fast instead of waiting for a click.
unset DISPLAY WAYLAND_DISPLAY
mkdir -p "$HOME/Downloads" "$HOME/Applications"
fails=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

# shellcheck source=../install.sh
READYLINUX_TEST=1 source "$repo/install.sh"
check "sourcing with READYLINUX_TEST runs nothing" '[[ ! -e "$KIT_STAMP" ]]'

# put_file: new, unchanged, updated.
f="$work/out/file.txt"
put_file "$f" <<< "one" >/dev/null
check "put_file writes a new file" '[[ "$(cat "$f")" == one && $KIT_CHANGED == 1 && ${#KIT_NEW[@]} == 1 ]]'
put_file "$f" <<< "one" >/dev/null
check "put_file leaves an unchanged file alone" '[[ $KIT_CHANGED == 0 && $KIT_SAME == 1 ]]'
put_file "$f" <<< "two" >/dev/null
check "put_file updates a changed file" '[[ "$(cat "$f")" == two && $KIT_CHANGED == 1 && ${#KIT_UPDATED[@]} == 1 ]]'

# fetch_image: keeps a JPEG, rejects an HTML error page. curl reads file:// URLs.
printf '\xff\xd8\xff\xe0fakejpeg' > "$work/ok.jpg"
printf '<html>404</html>' > "$work/bad.jpg"
check "fetch_image keeps a JPEG" 'fetch_image "file://$work/ok.jpg" "$work/got/ok.jpg" && [[ -s "$work/got/ok.jpg" ]]'
check "fetch_image rejects HTML" '! fetch_image "file://$work/bad.jpg" "$work/got/bad.jpg" 2>/dev/null && [[ ! -e "$work/got/bad.jpg" ]]'

# open-appimage, taken from install.sh. A fake AppImage that "extracts" an icon.
python3 "$repo/tests/embedded.py" open-appimage > "$work/open-appimage"
chmod +x "$work/open-appimage"
cat > "$HOME/Downloads/Demo App.AppImage" <<'APP'
#!/usr/bin/env bash
if [[ "${1:-}" == "--appimage-extract" ]]; then
  mkdir -p squashfs-root
  printf '\x89PNG fake' > squashfs-root/demo.png
  ln -s demo.png squashfs-root/.DirIcon
fi
APP
desk="$HOME/.local/share/applications/human-linux-appimage-Demo App.desktop"
"$work/open-appimage" --no-run "$HOME/Downloads/Demo App.AppImage" >/dev/null
check "open-appimage moves it to ~/Applications" '[[ -x "$HOME/Applications/Demo App.AppImage" && ! -e "$HOME/Downloads/Demo App.AppImage" ]]'
check "open-appimage writes a launcher" 'grep -qx "Exec=\"$HOME/Applications/Demo App.AppImage\"" "$desk"'
check "open-appimage uses the app icon" 'grep -qx "Icon=$HOME/.local/share/icons/Demo App.png" "$desk" && [[ -s "$HOME/.local/share/icons/Demo App.png" ]]'
check "open-appimage links it under AppFiles" '[[ -L "$HOME/Documents/AppFiles/appimages/Demo App.AppImage" ]]'
out="$("$work/open-appimage" --no-run "$HOME/Applications/Demo App.AppImage")"
check "open-appimage skips one already set up" '[[ "$out" == *"up to date"* ]]'
touch "$HOME/Downloads/notes.txt"
check "open-appimage refuses other files" '! "$work/open-appimage" --no-run "$HOME/Downloads/notes.txt" 2>/dev/null && [[ -e "$HOME/Downloads/notes.txt" ]]'

# A script cut off part way must not run anything when piped into bash.
head -n 400 "$repo/install.sh" > "$work/cut.sh"
out="$(bash "$work/cut.sh" 2>&1 < /dev/null)"
check "a cut-off install.sh runs nothing" '[[ "$out" != *"==>"* ]]'

echo
if ((fails)); then
  echo "$fails test(s) failed"
  exit 1
fi
echo "all passed"
