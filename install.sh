#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR_CREATED=""

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
UDEV_DIR="${UDEV_DIR:-/etc/udev/rules.d}"
STATE_DIR="${STATE_DIR:-/var/lib/veeam-usb-auto}"

SERVICE_NAME="veeam-usb-auto.service"
UDEV_RULE_NAME="99-veeam-usb-auto.rules"

JOB_ID="${JOB_ID:-50e035c0-8603-4a9d-943f-dba89b8ada90}"
JOB_NAME="${JOB_NAME:-HomeFolderBackup}"
MOUNTPOINT="${MOUNTPOINT:-/backup}"
REPO_PATH="${REPO_PATH:-/backup/veeam/linux}"
EXPECTED_UUID="${EXPECTED_UUID:-a42fe487-31b5-4e06-8fd2-d257725f0d82}"
DESKTOP_USER="${DESKTOP_USER:-lapinou}"
DESKTOP_UID="${DESKTOP_UID:-1000}"

AUTO_SCRIPT_SRC="$SCRIPT_DIR/scripts/veeam-usb-auto.sh"
NOTIFY_SCRIPT_SRC="$SCRIPT_DIR/scripts/veeam-notify-desktop.sh"
SERVICE_SRC="$SCRIPT_DIR/systemd/$SERVICE_NAME"
UDEV_RULE_SRC="$SCRIPT_DIR/udev/$UDEV_RULE_NAME"

AUTO_SCRIPT_DST="$BIN_DIR/veeam-usb-auto.sh"
NOTIFY_SCRIPT_DST="$BIN_DIR/veeam-notify-desktop.sh"
SERVICE_DST="$SYSTEMD_DIR/$SERVICE_NAME"
UDEV_RULE_DST="$UDEV_DIR/$UDEV_RULE_NAME"

cleanup() {
  if [ -n "$TMPDIR_CREATED" ] && [ -d "$TMPDIR_CREATED" ]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERREUR: lance ce script avec sudo/root"
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERREUR: commande manquante: $1"
    exit 1
  }
}

need_file() {
  if [ ! -f "$1" ]; then
    echo "ERREUR: fichier introuvable: $1"
    exit 1
  fi
}

sed_escape_replacement() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

replace_var() {
  local file="$1"
  local name="$2"
  local value
  value="$(sed_escape_replacement "$3")"

  sed -i "s|^${name}=.*|${name}=\"${value}\"|" "$file"
}

prepare_customized_files() {
  TMPDIR_CREATED="$(mktemp -d)"

  cp "$AUTO_SCRIPT_SRC" "$TMPDIR_CREATED/veeam-usb-auto.sh"
  cp "$NOTIFY_SCRIPT_SRC" "$TMPDIR_CREATED/veeam-notify-desktop.sh"
  cp "$SERVICE_SRC" "$TMPDIR_CREATED/$SERVICE_NAME"
  cp "$UDEV_RULE_SRC" "$TMPDIR_CREATED/$UDEV_RULE_NAME"

  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "JOB_ID" "$JOB_ID"
  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "JOB_NAME" "$JOB_NAME"
  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "MOUNTPOINT" "$MOUNTPOINT"
  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "REPO_PATH" "$REPO_PATH"
  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "EXPECTED_UUID" "$EXPECTED_UUID"
  replace_var "$TMPDIR_CREATED/veeam-usb-auto.sh" "STATE_DIR" "$STATE_DIR"

  replace_var "$TMPDIR_CREATED/veeam-notify-desktop.sh" "USER_NAME" "$DESKTOP_USER"
  replace_var "$TMPDIR_CREATED/veeam-notify-desktop.sh" "USER_ID" "$DESKTOP_UID"

  sed -i "s|^ExecStart=.*|ExecStart=$AUTO_SCRIPT_DST|" "$TMPDIR_CREATED/$SERVICE_NAME"
  sed -i "s|@EXPECTED_UUID@|$(sed_escape_replacement "$EXPECTED_UUID")|g" "$TMPDIR_CREATED/$UDEV_RULE_NAME"
  sed -i "s|@SERVICE_NAME@|$(sed_escape_replacement "$SERVICE_NAME")|g" "$TMPDIR_CREATED/$UDEV_RULE_NAME"
}

install_scripts() {
  install -d -m 0755 "$BIN_DIR"
  install -m 0755 "$TMPDIR_CREATED/veeam-usb-auto.sh" "$AUTO_SCRIPT_DST"
  install -m 0755 "$TMPDIR_CREATED/veeam-notify-desktop.sh" "$NOTIFY_SCRIPT_DST"
}

install_systemd_service() {
  install -d -m 0755 "$SYSTEMD_DIR"
  install -m 0644 "$TMPDIR_CREATED/$SERVICE_NAME" "$SERVICE_DST"
  systemctl daemon-reload
}

install_udev_rule() {
  install -d -m 0755 "$UDEV_DIR"
  install -m 0644 "$TMPDIR_CREATED/$UDEV_RULE_NAME" "$UDEV_RULE_DST"
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=block --property-match=ID_FS_UUID="$EXPECTED_UUID" || true
}

print_summary() {
  cat <<SUMMARY
[INSTALL] Terminé

Scripts installés:
  - $AUTO_SCRIPT_DST
  - $NOTIFY_SCRIPT_DST

Service systemd:
  - $SERVICE_DST

Règle udev:
  - $UDEV_RULE_DST

Configuration:
  - JOB_NAME=$JOB_NAME
  - JOB_ID=$JOB_ID
  - EXPECTED_UUID=$EXPECTED_UUID
  - MOUNTPOINT=$MOUNTPOINT
  - REPO_PATH=$REPO_PATH
  - DESKTOP_USER=$DESKTOP_USER
  - DESKTOP_UID=$DESKTOP_UID

Test manuel possible:
  sudo systemctl start $SERVICE_NAME
  journalctl -u $SERVICE_NAME -f
SUMMARY
}

main() {
  trap cleanup EXIT

  need_root

  need_cmd chmod
  need_cmd cp
  need_cmd install
  need_cmd mktemp
  need_cmd sed
  need_cmd systemctl
  need_cmd udevadm

  need_file "$AUTO_SCRIPT_SRC"
  need_file "$NOTIFY_SCRIPT_SRC"
  need_file "$SERVICE_SRC"
  need_file "$UDEV_RULE_SRC"

  echo "[INSTALL] Préparation des fichiers"
  prepare_customized_files

  echo "[INSTALL] Installation des scripts"
  install_scripts

  echo "[INSTALL] Installation du service systemd"
  install_systemd_service

  echo "[INSTALL] Installation de la règle udev"
  install_udev_rule

  print_summary
}

main "$@"
