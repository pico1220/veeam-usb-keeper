#!/bin/bash
set -euo pipefail

JOB_ID="@JOB_ID@"
JOB_NAME="@JOB_NAME@"

MOUNTPOINT="@MOUNTPOINT@"
REPO_PATH="@REPO_PATH@"
EXPECTED_UUID="@EXPECTED_UUID@"

LOCKFILE="/run/veeam-usb-auto.lock"
STATE_DIR="@STATE_DIR@"
MONTH_MARKER="$STATE_DIR/last-monthly-full"

exec 9>"$LOCKFILE"
if ! flock -n 9; then
  exit 0
fi

log() {
  logger -t veeam-usb-auto "$1"
  echo "$1"
}

notify() {
  /usr/local/bin/veeam-notify-desktop.sh "$1" || true
}

finish_keep_mounted() {
  log "Synchronisation finale"
  sync
  sleep 5
  log "Backup terminé, disque laissé monté pour inspection"
}

notify START
log "Début workflow backup USB"

for i in {1..30}; do
  [ -e "/dev/disk/by-uuid/$EXPECTED_UUID" ] && break
  sleep 1
done

if [ ! -e "/dev/disk/by-uuid/$EXPECTED_UUID" ]; then
  log "ERREUR: disque UUID $EXPECTED_UUID introuvable"
  notify FAILED
  exit 1
fi

DEVICE_LINK="/dev/disk/by-uuid/$EXPECTED_UUID"
DEVICE_REAL="$(readlink -f "$DEVICE_LINK")"

mkdir -p "$MOUNTPOINT"

# Cas 1 : /backup est déjà monté
if mountpoint -q "$MOUNTPOINT"; then
  CURRENT_SOURCE="$(findmnt -rn -o SOURCE --mountpoint "$MOUNTPOINT" || true)"
  CURRENT_REAL="$(readlink -f "$CURRENT_SOURCE" 2>/dev/null || echo "$CURRENT_SOURCE")"

  if [ "$CURRENT_REAL" = "$DEVICE_REAL" ]; then
    log "Disque déjà monté sur $MOUNTPOINT, on continue"
  else
    log "ERREUR: $MOUNTPOINT est monté avec $CURRENT_SOURCE au lieu de $DEVICE_REAL"
    notify FAILED
    exit 1
  fi

else
  # Cas 2 : le disque attendu est déjà monté ailleurs
  EXISTING_MP="$(findmnt -rn -S "$DEVICE_REAL" -o TARGET | head -n1 || true)"

  if [ -n "$EXISTING_MP" ]; then
    log "Disque déjà monté sur $EXISTING_MP, déplacement vers $MOUNTPOINT"

    mount --move "$EXISTING_MP" "$MOUNTPOINT" || {
      log "ERREUR: impossible de déplacer le montage de $EXISTING_MP vers $MOUNTPOINT"
      notify FAILED
      exit 1
    }

  else
    # Cas 3 : le disque n'est pas monté, montage normal via /etc/fstab
    mount "$MOUNTPOINT" || {
      log "ERREUR: échec du montage de $MOUNTPOINT"
      notify FAILED
      exit 1
    }
  fi
fi

# Vérification finale stricte
if ! mountpoint -q "$MOUNTPOINT"; then
  log "ERREUR: $MOUNTPOINT non monté"
  notify FAILED
  exit 1
fi

ACTUAL_SOURCE="$(findmnt -rn -o SOURCE --mountpoint "$MOUNTPOINT" || true)"
ACTUAL_REAL="$(readlink -f "$ACTUAL_SOURCE" 2>/dev/null || echo "$ACTUAL_SOURCE")"

if [ "$ACTUAL_REAL" != "$DEVICE_REAL" ]; then
  log "ERREUR: mauvais disque monté sur $MOUNTPOINT: $ACTUAL_SOURCE au lieu de $DEVICE_REAL"
  notify FAILED
  exit 1
fi

log "Montage validé: $DEVICE_REAL sur $MOUNTPOINT"

if [ ! -d "$REPO_PATH" ]; then
  log "ERREUR: repository absent: $REPO_PATH"
  notify FAILED
  exit 1
fi

if veeamconfig session list | grep -q "Working"; then
  log "ERREUR: session Veeam déjà en cours"
  notify FAILED
  exit 1
fi

mkdir -p "$STATE_DIR"

CURRENT_MONTH="$(date +%Y-%m)"
BACKUP_MODE="incremental"

if [ ! -f "$MONTH_MARKER" ] || [ "$(cat "$MONTH_MARKER")" != "$CURRENT_MONTH" ]; then
  BACKUP_MODE="activefull-monthly"
fi

log "Mode backup sélectionné: $BACKUP_MODE"

if [ "$BACKUP_MODE" = "activefull-monthly" ]; then
  notify RUNNING_FULL
  log "Lancement active full mensuel"
  START_OUTPUT="$(veeamconfig job start --name "$JOB_NAME" --activefull)"
else
  notify RUNNING
  log "Lancement incrémental"
  START_OUTPUT="$(veeamconfig job start --name "$JOB_NAME")"
fi

echo "$START_OUTPUT"

SESSION_ID="$(echo "$START_OUTPUT" | sed -n 's/.*Session ID: \[{\(.*\)}\].*/\1/p')"

if [ -z "$SESSION_ID" ]; then
  log "ERREUR: Session ID introuvable"
  notify FAILED
  exit 1
fi

log "Session Veeam: $SESSION_ID"

while true; do
  SESSION_LINE="$(veeamconfig session list --24 --jobId "$JOB_ID" | grep "{$SESSION_ID}" || true)"

  if [ -n "$SESSION_LINE" ]; then
    STATE="$(echo "$SESSION_LINE" | awk '{print $4}')"
    log "État session: $STATE"

    case "$STATE" in
      Running|Working)
        sleep 15
        ;;

      Success)
        log "Backup terminé avec succès, attente de stabilisation I/O"
        sleep 15
        sync

        if [ "$BACKUP_MODE" = "activefull-monthly" ]; then
          echo "$CURRENT_MONTH" > "$MONTH_MARKER"
          log "Active full mensuel validé pour $CURRENT_MONTH"
          notify SUCCESS_FULL_MOUNTED
        else
          notify SUCCESS_MOUNTED
        fi

        finish_keep_mounted
        exit 0
        ;;

      Warning)
        log "Backup terminé avec avertissement, attente de stabilisation I/O"
        sleep 15
        sync

        if [ "$BACKUP_MODE" = "activefull-monthly" ]; then
          echo "$CURRENT_MONTH" > "$MONTH_MARKER"
          log "Active full mensuel validé avec avertissement pour $CURRENT_MONTH"
          notify WARNING_FULL_MOUNTED
        else
          notify WARNING_MOUNTED
        fi

        finish_keep_mounted
        exit 0
        ;;

      Failed|Stopped)
        notify FAILED
        exit 1
        ;;

      *)
        sleep 15
        ;;
    esac
  else
    log "Session pas encore visible dans la liste"
    sleep 15
  fi
done