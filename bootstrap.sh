#!/bin/bash
set -euo pipefail

OWNER="${OWNER:-TON_USER_OU_ORG}"
REPO="${REPO:-veeam-usb-auto}"
REF="${REF:-main}"

INSTALL_DIR="${INSTALL_DIR:-/tmp/veeam-usb-auto-install}"
ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/heads/${REF}.tar.gz"

if [ "$REF" != "main" ] && [ "$REF" != "master" ]; then
  ARCHIVE_URL="https://github.com/${OWNER}/${REPO}/archive/refs/tags/${REF}.tar.gz"
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERREUR: commande manquante: $1"
    exit 1
  }
}

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR: lance ce script avec sudo/root"
  exit 1
fi

need_cmd curl
need_cmd tar
need_cmd mktemp

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "[INSTALL] Téléchargement depuis: $ARCHIVE_URL"

curl -fsSL "$ARCHIVE_URL" -o "$TMPDIR/source.tar.gz"

mkdir -p "$INSTALL_DIR"
tar -xzf "$TMPDIR/source.tar.gz" -C "$TMPDIR"

SRC_DIR="$(find "$TMPDIR" -maxdepth 1 -type d -name "${REPO}-*" | head -n 1)"

if [ -z "$SRC_DIR" ]; then
  echo "ERREUR: archive invalide, dossier source introuvable"
  exit 1
fi

rm -rf "$INSTALL_DIR"
cp -a "$SRC_DIR" "$INSTALL_DIR"

cd "$INSTALL_DIR"

if [ ! -f "./install.sh" ]; then
  echo "ERREUR: install.sh introuvable dans le dépôt"
  exit 1
fi

chmod +x ./install.sh

echo "[INSTALL] Lancement de install.sh"
./install.sh "$@"

echo "[INSTALL] Terminé"Add web bootstrap installer