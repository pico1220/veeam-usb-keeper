#!/bin/bash
set -euo pipefail

STATUS="${1:-INFO}"

USER_NAME="@DESKTOP_USER@"
USER_ID="@DESKTOP_UID@"

case "$STATUS" in
  START)
    MSG="Sauvegarde Veeam démarrée."
    URGENCY="normal"
    ;;

  RUNNING)
    MSG="Sauvegarde Veeam en cours."
    URGENCY="low"
    ;;

  RUNNING_FULL)
    MSG="Sauvegarde Veeam en cours : active full mensuel."
    URGENCY="normal"
    ;;

  SUCCESS_MOUNTED)
    MSG="Backup terminé avec succès. Le disque reste monté pour inspection. Démonte-le manuellement avant retrait."
    URGENCY="normal"
    ;;

  WARNING_MOUNTED)
    MSG="Backup terminé avec avertissement. Le disque reste monté pour inspection. Vérifie Veeam avant retrait."
    URGENCY="normal"
    ;;

  SUCCESS_FULL_MOUNTED)
    MSG="Active full mensuel terminé avec succès. Le disque reste monté pour inspection. Démonte-le manuellement avant retrait."
    URGENCY="normal"
    ;;

  WARNING_FULL_MOUNTED)
    MSG="Active full mensuel terminé avec avertissement. Vérifie Veeam avant retrait."
    URGENCY="normal"
    ;;

  FAILED)
    MSG="Sauvegarde Veeam échouée. Vérifie les logs avant de retirer le disque."
    URGENCY="critical"
    ;;

  *)
    MSG="Statut Veeam inconnu."
    URGENCY="low"
    ;;
esac

runuser -u "$USER_NAME" -- env \
  DISPLAY=:0 \
  XDG_RUNTIME_DIR="/run/user/$USER_ID" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
  notify-send -u "$URGENCY" "Veeam Backup" "$MSG"