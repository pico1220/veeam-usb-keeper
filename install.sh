#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR_CREATED=""

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
UDEV_DIR="${UDEV_DIR:-/etc/udev/rules.d}"
STATE_DIR="${STATE_DIR:-/var/lib/veeam-usb-auto}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/config.env}"
LOAD_CONFIG="auto"
INSTALL_TEST_MODE="${INSTALL_TEST_MODE:-0}"

SERVICE_NAME="veeam-usb-auto.service"
UDEV_RULE_NAME="99-veeam-usb-auto.rules"

JOB_ID="${JOB_ID:-}"
JOB_NAME="${JOB_NAME:-}"
MOUNTPOINT="${MOUNTPOINT:-/backup}"
REPO_PATH="${REPO_PATH:-}"
EXPECTED_UUID="${EXPECTED_UUID:-}"
DESKTOP_USER="${DESKTOP_USER:-${SUDO_USER:-}}"
DESKTOP_UID="${DESKTOP_UID:-}"

AUTO_SCRIPT_SRC="$SCRIPT_DIR/scripts/veeam-usb-auto.sh"
NOTIFY_SCRIPT_SRC="$SCRIPT_DIR/scripts/veeam-notify-desktop.sh"
SERVICE_SRC="$SCRIPT_DIR/systemd/$SERVICE_NAME"
UDEV_RULE_SRC="$SCRIPT_DIR/udev/$UDEV_RULE_NAME"

AUTO_SCRIPT_DST=""
NOTIFY_SCRIPT_DST=""
SERVICE_DST=""
UDEV_RULE_DST=""

usage() {
  cat <<USAGE
Usage: sudo ./install.sh [--config FILE] [--no-config]

Options:
  --config FILE  Charger les variables depuis FILE
  --no-config    Ne pas charger de fichier config.env
  -h, --help     Afficher cette aide

Copie config.env.example vers config.env, adapte les valeurs, puis relance l'installation.
USAGE
}

cleanup() {
  if [ -n "$TMPDIR_CREATED" ] && [ -d "$TMPDIR_CREATED" ]; then
    rm -rf "$TMPDIR_CREATED"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config)
        if [ "$#" -lt 2 ]; then
          echo "ERREUR: --config attend un chemin"
          usage
          exit 1
        fi
        CONFIG_FILE="$2"
        LOAD_CONFIG="yes"
        shift
        ;;
      --no-config)
        LOAD_CONFIG="no"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERREUR: option inconnue: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

need_root() {
  if [ "$INSTALL_TEST_MODE" = "1" ]; then
    return
  fi

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

load_config_file() {
  case "$LOAD_CONFIG" in
    no)
      return
      ;;
    auto)
      [ -f "$CONFIG_FILE" ] || return
      ;;
    yes)
      need_file "$CONFIG_FILE"
      ;;
  esac

  set -a
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  set +a
}

apply_defaults() {
  MOUNTPOINT="${MOUNTPOINT:-/backup}"
  STATE_DIR="${STATE_DIR:-/var/lib/veeam-usb-auto}"
  DESKTOP_USER="${DESKTOP_USER:-${SUDO_USER:-}}"

  if [ -z "$DESKTOP_UID" ] && [ -n "$DESKTOP_USER" ]; then
    DESKTOP_UID="$(id -u "$DESKTOP_USER" 2>/dev/null || true)"
  fi
}

require_var() {
  local name="$1"
  local value
  eval "value=\${$name:-}"

  if [ -z "$value" ]; then
    echo "ERREUR: variable obligatoire manquante: $name"
    return 1
  fi
}

reject_placeholder() {
  local name="$1"
  local bad_value="$2"
  local value
  eval "value=\${$name:-}"

  if [ "$value" = "$bad_value" ]; then
    echo "ERREUR: variable a personnaliser: $name vaut encore $bad_value"
    return 1
  fi
}

validate_uuid_var() {
  local name="$1"
  local value
  eval "value=\${$name:-}"

  case "$value" in
    ????????-????-????-????-????????????)
      ;;
    *)
      echo "ERREUR: format UUID invalide pour $name: $value"
      return 1
      ;;
  esac
}

validate_desktop_user() {
  local actual_uid

  if ! actual_uid="$(id -u "$DESKTOP_USER" 2>/dev/null)"; then
    echo "ERREUR: utilisateur desktop introuvable: $DESKTOP_USER"
    return 1
  fi

  if [ "$actual_uid" != "$DESKTOP_UID" ]; then
    echo "ERREUR: DESKTOP_UID=$DESKTOP_UID ne correspond pas a $DESKTOP_USER (UID reel: $actual_uid)"
    return 1
  fi
}

validate_expected_uuid_present() {
  if [ ! -e "/dev/disk/by-uuid/$EXPECTED_UUID" ]; then
    echo "ERREUR: UUID introuvable sur cette machine: $EXPECTED_UUID"
    echo "       Branche le disque attendu ou verifie EXPECTED_UUID avec lsblk -f."
    return 1
  fi
}

validate_fstab_entry() {
  if [ ! -f /etc/fstab ]; then
    echo "ERREUR: fichier /etc/fstab introuvable"
    return 1
  fi

  if ! awk -v uuid="$EXPECTED_UUID" -v mountpoint="$MOUNTPOINT" '
    /^[[:space:]]*($|#)/ { next }
    ($1 == "UUID=" uuid || $1 == "/dev/disk/by-uuid/" uuid) && $2 == mountpoint { found = 1 }
    END { exit(found ? 0 : 1) }
  ' /etc/fstab; then
    echo "ERREUR: aucune entree /etc/fstab ne monte UUID=$EXPECTED_UUID sur $MOUNTPOINT"
    return 1
  fi
}

validate_veeam_job() {
  local jobs
  local job_line

  if ! jobs="$(veeamconfig job list 2>&1)"; then
    echo "ERREUR: impossible de lister les jobs Veeam avec veeamconfig job list"
    echo "$jobs"
    return 1
  fi

  if ! printf '%s\n' "$jobs" | grep -F "{$JOB_ID}" >/dev/null; then
    echo "ERREUR: job Veeam introuvable pour JOB_ID=$JOB_ID"
    return 1
  fi

  if ! printf '%s\n' "$jobs" | grep -F "$JOB_NAME" >/dev/null; then
    echo "ERREUR: job Veeam introuvable pour JOB_NAME=$JOB_NAME"
    return 1
  fi

  job_line="$(printf '%s\n' "$jobs" | grep -F "{$JOB_ID}" | grep -F "$JOB_NAME" | head -n1 || true)"
  if [ -z "$job_line" ]; then
    echo "ERREUR: JOB_ID et JOB_NAME ne correspondent pas au meme job Veeam"
    echo "       JOB_ID=$JOB_ID"
    echo "       JOB_NAME=$JOB_NAME"
    return 1
  fi
}

compute_install_paths() {
  AUTO_SCRIPT_DST="$BIN_DIR/veeam-usb-auto.sh"
  NOTIFY_SCRIPT_DST="$BIN_DIR/veeam-notify-desktop.sh"
  SERVICE_DST="$SYSTEMD_DIR/$SERVICE_NAME"
  UDEV_RULE_DST="$UDEV_DIR/$UDEV_RULE_NAME"
}

validate_config() {
  local missing=0

  require_var JOB_NAME || missing=1
  require_var JOB_ID || missing=1
  require_var EXPECTED_UUID || missing=1
  require_var MOUNTPOINT || missing=1
  require_var REPO_PATH || missing=1
  require_var DESKTOP_USER || missing=1
  require_var DESKTOP_UID || missing=1
  require_var STATE_DIR || missing=1

  if [ "$missing" -eq 0 ]; then
    reject_placeholder JOB_NAME "MonJobVeeam" || missing=1
    reject_placeholder JOB_ID "00000000-0000-0000-0000-000000000000" || missing=1
    reject_placeholder EXPECTED_UUID "00000000-0000-0000-0000-000000000000" || missing=1
    reject_placeholder DESKTOP_USER "ton-utilisateur" || missing=1
    validate_uuid_var JOB_ID || missing=1
    validate_uuid_var EXPECTED_UUID || missing=1
  fi

  if [ "$missing" -eq 0 ]; then
    if [ "$INSTALL_TEST_MODE" = "1" ]; then
      return
    fi

    validate_desktop_user || missing=1
    validate_expected_uuid_present || missing=1
    validate_fstab_entry || missing=1
    validate_veeam_job || missing=1
  fi

  if [ "$missing" -ne 0 ]; then
    cat <<ERROR

Copie le fichier d'exemple puis renseigne tes valeurs:
  cp config.env.example config.env
  sudo ./install.sh --config config.env

Tu peux aussi passer les variables en environnement.
ERROR
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

  if [ "$INSTALL_TEST_MODE" != "1" ]; then
    systemctl daemon-reload
  fi
}

install_udev_rule() {
  install -d -m 0755 "$UDEV_DIR"
  install -m 0644 "$TMPDIR_CREATED/$UDEV_RULE_NAME" "$UDEV_RULE_DST"

  if [ "$INSTALL_TEST_MODE" != "1" ]; then
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=block --property-match=ID_FS_UUID="$EXPECTED_UUID" || true
  fi
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

  parse_args "$@"
  need_root

  need_cmd chmod
  need_cmd cp
  need_cmd install
  need_cmd mktemp
  need_cmd sed
  need_cmd awk
  need_cmd grep
  need_cmd head
  need_cmd id

  if [ "$INSTALL_TEST_MODE" != "1" ]; then
    need_cmd systemctl
    need_cmd udevadm
    need_cmd veeamconfig
  fi

  need_file "$AUTO_SCRIPT_SRC"
  need_file "$NOTIFY_SCRIPT_SRC"
  need_file "$SERVICE_SRC"
  need_file "$UDEV_RULE_SRC"

  load_config_file
  apply_defaults
  compute_install_paths
  validate_config

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
