#!/bin/bash
set -euo pipefail

BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
UDEV_DIR="${UDEV_DIR:-/etc/udev/rules.d}"
STATE_DIR="${STATE_DIR:-/var/lib/veeam-usb-auto}"

SERVICE_NAME="veeam-usb-auto.service"
UDEV_RULE_NAME="99-veeam-usb-auto.rules"

AUTO_SCRIPT_DST="$BIN_DIR/veeam-usb-auto.sh"
NOTIFY_SCRIPT_DST="$BIN_DIR/veeam-notify-desktop.sh"
SERVICE_DST="$SYSTEMD_DIR/$SERVICE_NAME"
UDEV_RULE_DST="$UDEV_DIR/$UDEV_RULE_NAME"

STATE_ACTION="ask"

usage() {
  cat <<USAGE
Usage: sudo ./uninstall.sh [--keep-state|--purge-state]

Options:
  --keep-state   Conserver $STATE_DIR
  --purge-state  Supprimer $STATE_DIR
  -h, --help     Afficher cette aide
USAGE
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

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --keep-state)
        STATE_ACTION="keep"
        ;;
      --purge-state)
        STATE_ACTION="purge"
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

remove_file() {
  local path="$1"

  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -f "$path"
    echo "[UNINSTALL] Supprimé: $path"
  else
    echo "[UNINSTALL] Déjà absent: $path"
  fi
}

stop_and_disable_service() {
  if systemctl list-unit-files "$SERVICE_NAME" >/dev/null 2>&1 || [ -f "$SERVICE_DST" ]; then
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl reset-failed "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
}

reload_systemd() {
  systemctl daemon-reload
  systemctl reset-failed >/dev/null 2>&1 || true
}

reload_udev() {
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=block || true
}

confirm_purge_state() {
  local answer

  if [ ! -d "$STATE_DIR" ]; then
    echo "[UNINSTALL] Dossier d'etat deja absent: $STATE_DIR"
    return
  fi

  case "$STATE_ACTION" in
    keep)
      echo "[UNINSTALL] Dossier d'etat conserve: $STATE_DIR"
      ;;
    purge)
      rm -rf "$STATE_DIR"
      echo "[UNINSTALL] Dossier d'etat supprime: $STATE_DIR"
      ;;
    ask)
      printf "Supprimer le dossier d'etat %s ? [y/N] " "$STATE_DIR"
      read -r answer
      case "$answer" in
        y|Y|yes|YES|o|O|oui|OUI)
          rm -rf "$STATE_DIR"
          echo "[UNINSTALL] Dossier d'etat supprime: $STATE_DIR"
          ;;
        *)
          echo "[UNINSTALL] Dossier d'etat conserve: $STATE_DIR"
          ;;
      esac
      ;;
  esac
}

print_summary() {
  cat <<SUMMARY
[UNINSTALL] Termine

Elements retires:
  - $AUTO_SCRIPT_DST
  - $NOTIFY_SCRIPT_DST
  - $SERVICE_DST
  - $UDEV_RULE_DST

Dossier d'etat:
  - $STATE_DIR
SUMMARY
}

main() {
  parse_args "$@"
  need_root
  need_cmd rm
  need_cmd systemctl
  need_cmd udevadm

  echo "[UNINSTALL] Arret et desactivation du service"
  stop_and_disable_service

  echo "[UNINSTALL] Suppression des fichiers installes"
  remove_file "$SERVICE_DST"
  remove_file "$UDEV_RULE_DST"
  remove_file "$AUTO_SCRIPT_DST"
  remove_file "$NOTIFY_SCRIPT_DST"

  echo "[UNINSTALL] Rechargement systemd"
  reload_systemd

  echo "[UNINSTALL] Rechargement udev"
  reload_udev

  confirm_purge_state
  print_summary
}

main "$@"
