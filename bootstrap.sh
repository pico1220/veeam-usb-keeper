#!/bin/bash
set -euo pipefail

PROJECT_VERSION="0.1.0"

OWNER="${OWNER:-pico1220}"
REPO="${REPO:-veeam-usb-keeper}"
REF="${REF:-v$PROJECT_VERSION}"
REF_TYPE="${REF_TYPE:-auto}"

INSTALL_DIR="${INSTALL_DIR:-/tmp/veeam-usb-auto-install}"

usage() {
  cat <<USAGE
Usage: sudo bash bootstrap.sh [install.sh options]

Variables:
  OWNER        GitHub owner/org. Default: $OWNER
  REPO         GitHub repository. Default: $REPO
  REF          Git ref to install. Default: $REF
  REF_TYPE     auto, tag, or branch. Default: $REF_TYPE
  INSTALL_DIR  Temporary extracted source directory. Default: $INSTALL_DIR

Examples:
  sudo bash bootstrap.sh --config config.env
  sudo REF=v0.1.0 bash bootstrap.sh --no-config
  sudo REF=main REF_TYPE=branch bash bootstrap.sh --no-config
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERREUR: commande manquante: $1"
    exit 1
  }
}

archive_url() {
  case "$REF_TYPE" in
    tag)
      printf '%s\n' "https://github.com/$OWNER/$REPO/archive/refs/tags/$REF.tar.gz"
      ;;
    branch)
      printf '%s\n' "https://github.com/$OWNER/$REPO/archive/refs/heads/$REF.tar.gz"
      ;;
    auto)
      case "$REF" in
        main|master)
          printf '%s\n' "https://github.com/$OWNER/$REPO/archive/refs/heads/$REF.tar.gz"
          ;;
        *)
          printf '%s\n' "https://github.com/$OWNER/$REPO/archive/refs/tags/$REF.tar.gz"
          ;;
      esac
      ;;
    *)
      echo "ERREUR: REF_TYPE doit valoir auto, tag ou branch"
      exit 1
      ;;
  esac
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR: lance ce script avec sudo/root"
  exit 1
fi

need_cmd curl
need_cmd tar
need_cmd mktemp
need_cmd find
need_cmd cp
need_cmd rm
need_cmd chmod
need_cmd head
need_cmd mkdir

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ARCHIVE_URL="$(archive_url)"
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

echo "[INSTALL] Terminé"
