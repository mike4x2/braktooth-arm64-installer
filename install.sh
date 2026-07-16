#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="WDissector ARM64 Trixie installer"

GITHUB_REPO="mike4x2/braktooth-arm64-installer"
RELEASE_TAG="v0.1.0-arm64"
ARCHIVE_NAME="wdissector_aarch64.tar.zst"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${ARCHIVE_NAME}"

INSTALL_DIR="${INSTALL_DIR:-$HOME/wdissector}"
ARCHIVE="${1:-}"
EXPECTED_ARCH="aarch64"

TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"

GLIB_REAL="/usr/lib/aarch64-linux-gnu/glib-2.0/include/glibconfig.h"
GLIB_COMPAT_DIR="/usr/lib/x86_64-linux-gnu/glib-2.0/include"
GLIB_COMPAT="${GLIB_COMPAT_DIR}/glibconfig.h"

BULLSEYE_SOURCE="/etc/apt/sources.list.d/braktooth-compat.list"
BULLSEYE_PREF="/etc/apt/preferences.d/braktooth-compat"

MODULE_LOG="/tmp/wdissector-module-build.log"

log() {
  printf '\n[%s] %s\n' "$APP_NAME" "$*"
}

warn() {
  printf '\nWARNING: %s\n' "$*" >&2
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  rm -f /tmp/wdissector-glib-test.o
}

trap cleanup EXIT

[[ "$(uname -m)" == "$EXPECTED_ARCH" ]] ||
  die "This installer supports ARM64/aarch64 only. Detected: $(uname -m)"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${VERSION_CODENAME:-}" != "trixie" ]]; then
    warn "Tested on Debian 13 Trixie/Armbian ARM64; detected ${PRETTY_NAME:-unknown}."
  fi
fi

log "Installing Debian 13 build and runtime dependencies"

sudo apt-get update

sudo apt-get install -y \
  build-essential \
  ca-certificates \
  curl \
  pkg-config \
  zstd \
  libglib2.0-dev \
  libgoogle-glog-dev \
  libpcap-dev \
  libtbb12 \
  libtbbmalloc2 \
  libtbb-dev \
  libgl1 \
  libfreetype6 \
  libsnappy1v5 \
  libpulse0 \
  libc-ares2 \
  libxml2 \
  liblua5.2-0 \
  libsmi2ldbl

command -v g++ >/dev/null ||
  die "g++ was not installed."

command -v pkg-config >/dev/null ||
  die "pkg-config was not installed."

command -v curl >/dev/null ||
  die "curl was not installed."

command -v zstd >/dev/null ||
  die "zstd was not installed."

[[ -f "$GLIB_REAL" ]] ||
  die "Missing ARM64 GLib header: $GLIB_REAL"

log "Installing legacy ARM64 compatibility libraries"

sudo tee "$BULLSEYE_SOURCE" >/dev/null <<'EOF'
deb http://deb.debian.org/debian bullseye main
deb http://security.debian.org/debian-security bullseye-security main
EOF

sudo tee "$BULLSEYE_PREF" >/dev/null <<'EOF'
Package: *
Pin: release n=bullseye
Pin-Priority: 50
EOF

sudo apt-get update

sudo apt-get install -y \
  libssl1.1/bullseye \
  libgoogle-glog0v5/bullseye

sudo ldconfig

log "Checking serial-port permissions"

DIALOUT_ACTIVATION_NEEDED=0

if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx dialout; then
  printf '%s is already a member of dialout.\n' "$TARGET_USER"
else
  sudo usermod -aG dialout "$TARGET_USER"
  DIALOUT_ACTIVATION_NEEDED=1

  printf "\nUser '%s' was added to the dialout group.\n" "$TARGET_USER"
  printf 'Log out and back in before opening /dev/ttyUSB* or /dev/ttyACM*.\n'
  printf 'A reboot also works, but is not required.\n'
fi

log "Creating compatibility header path required by the prebuilt module compiler"

sudo mkdir -p "$GLIB_COMPAT_DIR"

if [[ -e "$GLIB_COMPAT" || -L "$GLIB_COMPAT" ]]; then
  sudo rm -f "$GLIB_COMPAT"
fi

sudo ln -s "$GLIB_REAL" "$GLIB_COMPAT"

[[ "$(readlink -f "$GLIB_COMPAT")" == "$GLIB_REAL" ]] ||
  die "GLib compatibility link did not resolve correctly."

log "Testing GLib C++ compilation"

printf '#include <glib.h>\nint main(){return 0;}\n' |
  g++ \
    -x c++ \
    -c \
    -o /tmp/wdissector-glib-test.o \
    -I/usr/include/glib-2.0 \
    -I/usr/lib/x86_64-linux-gnu/glib-2.0/include \
    -

resolve_archive() {
  if [[ -n "$ARCHIVE" ]]; then
    ARCHIVE="$(readlink -f "$ARCHIVE" 2>/dev/null || true)"
    [[ -n "$ARCHIVE" && -f "$ARCHIVE" ]] ||
      die "Archive not found: ${1:-unknown}"
    return
  fi

  if [[ -f "./$ARCHIVE_NAME" ]]; then
    ARCHIVE="$(readlink -f "./$ARCHIVE_NAME")"
    return
  fi

  if [[ -f "$HOME/$ARCHIVE_NAME" ]]; then
    ARCHIVE="$(readlink -f "$HOME/$ARCHIVE_NAME")"
    return
  fi

  ARCHIVE="$PWD/$ARCHIVE_NAME"

  log "Downloading release archive"

  curl \
    --fail \
    --location \
    --progress-bar \
    --retry 4 \
    --retry-delay 3 \
    --retry-all-errors \
    "$DOWNLOAD_URL" \
    --output "$ARCHIVE"

  [[ -s "$ARCHIVE" ]] ||
    die "The downloaded archive is missing or empty."
}

if [[ -x ./bin/bt_exploiter && -z "${1:-}" ]]; then
  INSTALL_DIR="$PWD"
  log "Using existing WDissector tree at $INSTALL_DIR"
else
  resolve_archive "$ARCHIVE"

  mkdir -p "$INSTALL_DIR"

  log "Extracting $ARCHIVE into $INSTALL_DIR"

  tar \
    --zstd \
    -xf "$ARCHIVE" \
    -C "$INSTALL_DIR" \
    --strip-components=1
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

[[ -x ./bin/bt_exploiter ]] ||
  die "Missing executable: $INSTALL_DIR/bin/bt_exploiter"

log "Checking executable shared-library dependencies"

MISSING_LIBS="$(ldd ./bin/bt_exploiter 2>/dev/null |
  awk '/not found/ {print $1}' |
  sort -u || true)"

if [[ -n "$MISSING_LIBS" ]]; then
  printf '\nUnresolved libraries:\n%s\n' "$MISSING_LIBS" >&2

  if grep -qx 'libtbb.so.2' <<<"$MISSING_LIBS"; then
    cat >&2 <<'EOF'

The prebuilt executable requires legacy libtbb.so.2.
Do not symlink libtbb.so.12 to libtbb.so.2 because they use different ABIs.
EOF
  fi

  die "The main executable still has unresolved shared libraries."
fi

log "Removing stale generated Bluetooth module objects"

find modules/exploits/bluetooth \
  -maxdepth 1 \
  \( -name '*.o' -o -name '*.so' \) \
  -delete

log "Compiling and loading Bluetooth modules"

rm -f "$MODULE_LOG"
set +e

timeout --signal=INT --kill-after=10s 90s \
  ./bin/bt_exploiter --list-exploits \
  2>&1 |
  tee "$MODULE_LOG"

MODULE_STATUS=${PIPESTATUS[0]}
set -e

if grep -Eqi \
  'fatal error|failed to compile|undefined reference|cannot find' \
  "$MODULE_LOG"; then
  printf '\nModule compilation reported errors. Review:\n  %s\n' \
    "$MODULE_LOG" >&2
  exit 3
fi

if ! grep -Eq '\[Modules\][[:space:]]+24/24 Modules Compiled / Loaded' \
  "$MODULE_LOG"; then
  printf '\nThe expected 24/24 module result was not found. Review:\n  %s\n' \
    "$MODULE_LOG" >&2
  exit 4
fi

case "$MODULE_STATUS" in
  0)
    ;;
  124|130)
    printf '\nModule validation completed before the scanner was stopped.\n'
    ;;
  *)
    warn "bt_exploiter returned status $MODULE_STATUS after loading the modules."
    ;;
esac

log "Checking for USB serial devices"

mapfile -t SERIAL_DEVICES < <(
  compgen -G '/dev/ttyUSB*'
  compgen -G '/dev/ttyACM*'
  true
)

if ((${#SERIAL_DEVICES[@]})); then
  printf 'Detected serial devices:\n'

  for device in "${SERIAL_DEVICES[@]}"; do
    ls -l "$device"
  done
else
  warn "No /dev/ttyUSB* or /dev/ttyACM* devices are currently connected."
fi

log "Installation completed successfully"

printf 'Installed at: %s\n' "$INSTALL_DIR"
printf 'Module log: %s\n' "$MODULE_LOG"

cat <<EOF

Useful commands:

  cd "$INSTALL_DIR"

  # Show available serial ports
  ls -l /dev/ttyUSB* /dev/ttyACM* 2>/dev/null

  # Validate the installed executable and modules
  ./bin/bt_exploiter --list-exploits

  # Start with the ESP32 serial interface
  ./bin/bt_exploiter --host-port /dev/ttyUSB1

Use the actual /dev/ttyUSB* or /dev/ttyACM* device shown on your system.
EOF

if ((DIALOUT_ACTIVATION_NEEDED)); then
  cat <<EOF

IMPORTANT:
User '$TARGET_USER' was added to the dialout group during this installation.
Log out and back in before starting WDissector. A reboot is not required.
EOF
fi
