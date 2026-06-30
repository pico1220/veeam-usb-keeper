#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR_CREATED=""

cleanup() {
  if [ -n "$TMPDIR_CREATED" ] && [ -d "$TMPDIR_CREATED" ]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}

trap cleanup EXIT

log() {
  printf '[CHECK] %s\n' "$1"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

check_release_metadata() {
  local version
  local tag

  log "Metadonnees de release"
  version="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
  tag="v$version"

  [ -n "$version" ]
  grep -F "PROJECT_VERSION=\"$version\"" "$ROOT_DIR/bootstrap.sh" >/dev/null
  grep -F "REF=\"\${REF:-v\$PROJECT_VERSION}\"" "$ROOT_DIR/bootstrap.sh" >/dev/null
  grep -F "Version stable courante: \`$version\` (\`$tag\`)." "$ROOT_DIR/README.md" >/dev/null
  grep -F "raw.githubusercontent.com/pico1220/veeam-usb-keeper/$tag/bootstrap.sh" "$ROOT_DIR/README.md" >/dev/null
  grep -F "## [$version]" "$ROOT_DIR/CHANGELOG.md" >/dev/null
}

check_bash_syntax() {
  local file

  log "Syntaxe Bash"
  while IFS= read -r file; do
    bash -n "$ROOT_DIR/$file"
  done <<'FILES'
bootstrap.sh
check.sh
install.sh
scripts/veeam-notify-desktop.sh
scripts/veeam-usb-auto.sh
uninstall.sh
FILES
}

check_shellcheck() {
  local file

  if ! have_cmd shellcheck; then
    log "ShellCheck absent, etape ignoree"
    return
  fi

  log "ShellCheck"
  while IFS= read -r file; do
    shellcheck "$ROOT_DIR/$file"
  done <<'FILES'
bootstrap.sh
check.sh
install.sh
scripts/veeam-notify-desktop.sh
scripts/veeam-usb-auto.sh
uninstall.sh
FILES
}

check_systemd_template() {
  local service_file="$ROOT_DIR/systemd/veeam-usb-auto.service"

  if ! have_cmd systemd-analyze; then
    log "systemd-analyze absent, validation systemd ignoree"
    return
  fi

  log "Validation systemd"
  systemd-analyze verify "$service_file"
}

check_udev_template() {
  local rule_file="$ROOT_DIR/udev/99-veeam-usb-auto.rules"

  if ! have_cmd udevadm; then
    log "udevadm absent, validation udev ignoree"
    return
  fi

  if ! udevadm --help 2>/dev/null | grep -q 'verify'; then
    log "udevadm ne fournit pas verify, validation udev ignoree"
    return
  fi

  log "Validation udev"
  udevadm verify "$rule_file"
}

check_temp_install() {
  local bin_dir
  local systemd_dir
  local udev_dir
  local state_dir
  local expected_uuid="11111111-2222-3333-4444-555555555555"
  local job_id="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

  log "Installation temporaire"
  TMPDIR_CREATED="$(mktemp -d)"
  bin_dir="$TMPDIR_CREATED/bin"
  systemd_dir="$TMPDIR_CREATED/systemd"
  udev_dir="$TMPDIR_CREATED/udev"
  state_dir="$TMPDIR_CREATED/state"

  INSTALL_TEST_MODE=1 \
  BIN_DIR="$bin_dir" \
  SYSTEMD_DIR="$systemd_dir" \
  UDEV_DIR="$udev_dir" \
  STATE_DIR="$state_dir" \
  JOB_NAME="CheckJob" \
  JOB_ID="$job_id" \
  EXPECTED_UUID="$expected_uuid" \
  MOUNTPOINT="$TMPDIR_CREATED/mount" \
  REPO_PATH="$TMPDIR_CREATED/mount/repo" \
  DESKTOP_USER="check-user" \
  DESKTOP_UID="1000" \
    "$ROOT_DIR/install.sh" --no-config >/dev/null

  [ -x "$bin_dir/veeam-usb-auto.sh" ]
  [ -x "$bin_dir/veeam-notify-desktop.sh" ]
  [ -f "$systemd_dir/veeam-usb-auto.service" ]
  [ -f "$udev_dir/99-veeam-usb-auto.rules" ]

  grep -F "ExecStart=$bin_dir/veeam-usb-auto.sh" "$systemd_dir/veeam-usb-auto.service" >/dev/null
  grep -F "ENV{ID_FS_UUID}==\"$expected_uuid\"" "$udev_dir/99-veeam-usb-auto.rules" >/dev/null
  grep -F 'ENV{SYSTEMD_WANTS}+="veeam-usb-auto.service"' "$udev_dir/99-veeam-usb-auto.rules" >/dev/null
  grep -F "JOB_ID=\"$job_id\"" "$bin_dir/veeam-usb-auto.sh" >/dev/null
  grep -F "USER_NAME=\"check-user\"" "$bin_dir/veeam-notify-desktop.sh" >/dev/null
}

main() {
  check_release_metadata
  check_bash_syntax
  check_shellcheck
  check_systemd_template
  check_udev_template
  check_temp_install
  log "OK"
}

main "$@"
