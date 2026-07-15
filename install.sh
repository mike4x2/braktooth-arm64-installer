#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="WDissector ARM64 Trixie installer"
INSTALL_DIR="${INSTALL_DIR:-$HOME/wdissector}"
ARCHIVE="${1:-}"
EXPECTED_ARCH="aarch64"
GLIB_REAL="/usr/lib/aarch64-linux-gnu/glib-2.0/include/glibconfig.h"
GLIB_COMPAT_DIR="/usr/lib/x86_64-linux-gnu/glib-2.0/include"
GLIB_COMPAT="${GLIB_COMPAT_DIR}/glibconfig.h"

log() { printf '\n[%s] %s\n' "$APP_NAME" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "$EXPECTED_ARCH" ]] || die "This installer supports ARM64/aarch64 only."

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${ID:-}" != "debian" || "${VERSION_CODENAME:-}" != "trixie" ]]; then
    printf 'WARNING: Tested on Debian 13 (Trixie)/Armbian ARM64; detected %s %s.\n' \
      "${PRETTY_NAME:-unknown}" "${VERSION_CODENAME:-unknown}"
  fi
fi

log "Installing Debian 13 build/runtime dependencies"
sudo apt-get update
sudo apt-get install -y \
  build-essential \
  pkg-config \
  zstd \
  libglib2.0-dev \
  libgoogle-glog-dev \
  libpcap-dev \
  libtbb12 \
  libtbbmalloc2 \
  libtbb-dev

command -v g++ >/dev/null || die "g++ was not installed."
command -v pkg-config >/dev/null || die "pkg-config was not installed."
[[ -f "$GLIB_REAL" ]] || die "Missing ARM64 GLib header: $GLIB_REAL"

log "Creating compatibility header path required by the prebuilt module compiler"
sudo mkdir -p "$GLIB_COMPAT_DIR"
if [[ -e "$GLIB_COMPAT" || -L "$GLIB_COMPAT" ]]; then
  sudo rm -f "$GLIB_COMPAT"
fi
sudo ln -s "$GLIB_REAL" "$GLIB_COMPAT"

readlink -f "$GLIB_COMPAT" | grep -qx "$GLIB_REAL" \
  || die "GLib compatibility link did not resolve correctly."

log "Testing GLib C++ compilation"
printf '#include <glib.h>\nint main(){return 0;}\n' |
  g++ -x c++ -c -o /tmp/wdissector-glib-test.o \
    -I/usr/include/glib-2.0 \
    -I/usr/lib/x86_64-linux-gnu/glib-2.0/include -
rm -f /tmp/wdissector-glib-test.o

if [[ -n "$ARCHIVE" ]]; then
  [[ -f "$ARCHIVE" ]] || die "Archive not found: $ARCHIVE"
  mkdir -p "$INSTALL_DIR"
  log "Extracting $ARCHIVE into $INSTALL_DIR"
  tar --zstd -xf "$ARCHIVE" -C "$INSTALL_DIR" --strip-components=1
elif [[ -x ./bin/bt_exploiter ]]; then
  INSTALL_DIR="$PWD"
  log "Using existing WDissector tree at $INSTALL_DIR"
else
  die "Pass the WDissector .tar.zst archive as argument, or run this script from the extracted WDissector root."
fi

cd "$INSTALL_DIR"

if [[ -f requirements.sh ]]; then
  log "Patching obsolete Debian package names in requirements.sh"
  sed -i \
    -e 's/\blibtbb2\b/libtbb12 libtbbmalloc2/g' \
    -e 's/\blibgoogle-glog0v5\b/libgoogle-glog-dev/g' \
    -e 's/\bsoftware-properties-common\b//g' \
    requirements.sh
fi

[[ -x ./bin/bt_exploiter ]] || die "Missing executable: $INSTALL_DIR/bin/bt_exploiter"

if ldd ./bin/bt_exploiter 2>/dev/null | grep -q 'libtbb\.so\.2 => not found'; then
  cat >&2 <<'EOF'

The prebuilt executable requires legacy libtbb.so.2, but Debian 13 normally
ships a newer TBB ABI. Do not symlink libtbb.so.12 to libtbb.so.2.

Install a legitimate ARM64 libtbb2 compatibility package matching this build,
then rerun this installer. The installer intentionally stops instead of mixing
in an unverified old package automatically.
EOF
  exit 2
fi

if ldd ./bin/bt_exploiter 2>/dev/null | grep -q 'not found'; then
  ldd ./bin/bt_exploiter | grep 'not found' >&2
  die "The main executable still has unresolved shared libraries."
fi

log "Removing stale generated Bluetooth module objects"
find modules/exploits/bluetooth -maxdepth 1 \
  \( -name '*.o' -o -name '*.so' \) -delete

log "Compiling and listing modules"
./bin/bt_exploiter --list-exploits 2>&1 | tee /tmp/wdissector-module-build.log

if grep -Eqi 'fatal error|failed to compile|undefined reference|cannot find' \
  /tmp/wdissector-module-build.log; then
  printf '\nModule compilation reported errors. Review:\n  /tmp/wdissector-module-build.log\n' >&2
  exit 3
fi

log "Installation completed successfully"
printf 'Installed at: %s\n' "$INSTALL_DIR"
printf 'Test with: cd %q && ./bin/bt_exploiter --list-exploits\n' "$INSTALL_DIR"
