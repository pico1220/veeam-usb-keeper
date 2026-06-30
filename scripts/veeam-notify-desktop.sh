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

get_loginctl_prop() {
  local session_id="$1"
  local property="$2"

  loginctl show-session "$session_id" -p "$property" --value 2>/dev/null || true
}

find_graphical_session() {
  local session_id
  local uid
  local user
  local remote
  local session_type
  local state

  command -v loginctl >/dev/null 2>&1 || return 1

  while read -r session_id _; do
    [ -n "$session_id" ] || continue

    uid="$(get_loginctl_prop "$session_id" UID)"
    user="$(get_loginctl_prop "$session_id" Name)"
    remote="$(get_loginctl_prop "$session_id" Remote)"
    session_type="$(get_loginctl_prop "$session_id" Type)"
    state="$(get_loginctl_prop "$session_id" State)"

    [ "$uid" = "$USER_ID" ] || [ "$user" = "$USER_NAME" ] || continue
    [ "$remote" = "no" ] || continue

    case "$session_type" in
      x11|wayland)
        ;;
      *)
        continue
        ;;
    esac

    case "$state" in
      active|online)
        printf '%s\n' "$session_id"
        return 0
        ;;
    esac
  done <<EOF
$(loginctl list-sessions --no-legend 2>/dev/null || true)
EOF

  return 1
}

notify_env() {
  local session_id="$1"
  local runtime_dir="/run/user/$USER_ID"
  local dbus_address="unix:path=$runtime_dir/bus"
  local session_type=""
  local display=""
  local wayland_display=""
  local wayland_socket

  [ -S "$runtime_dir/bus" ] || return 1

  if [ -n "$session_id" ]; then
    session_type="$(get_loginctl_prop "$session_id" Type)"
    display="$(get_loginctl_prop "$session_id" Display)"
  fi

  if [ "$session_type" = "wayland" ]; then
    for wayland_socket in "$runtime_dir"/wayland-*; do
      [ -S "$wayland_socket" ] || continue
      wayland_display="$(basename "$wayland_socket")"
      break
    done
  fi

  if [ -n "$display" ] && [ -n "$wayland_display" ]; then
    runuser -u "$USER_NAME" -- env \
      XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
      XDG_SESSION_TYPE="$session_type" \
      DISPLAY="$display" \
      WAYLAND_DISPLAY="$wayland_display" \
      notify-send -u "$URGENCY" "Veeam Backup" "$MSG"
  elif [ -n "$display" ]; then
    runuser -u "$USER_NAME" -- env \
      XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
      XDG_SESSION_TYPE="$session_type" \
      DISPLAY="$display" \
      notify-send -u "$URGENCY" "Veeam Backup" "$MSG"
  elif [ -n "$wayland_display" ]; then
    runuser -u "$USER_NAME" -- env \
      XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
      XDG_SESSION_TYPE="$session_type" \
      WAYLAND_DISPLAY="$wayland_display" \
      notify-send -u "$URGENCY" "Veeam Backup" "$MSG"
  else
    runuser -u "$USER_NAME" -- env \
      XDG_RUNTIME_DIR="$runtime_dir" \
      DBUS_SESSION_BUS_ADDRESS="$dbus_address" \
      XDG_SESSION_TYPE="$session_type" \
      notify-send -u "$URGENCY" "Veeam Backup" "$MSG"
  fi
}

SESSION_ID="$(find_graphical_session || true)"
notify_env "$SESSION_ID"
