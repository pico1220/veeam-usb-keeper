# Changelog

Toutes les modifications notables de ce projet sont documentees ici.

Le projet suit des tags Git `vMAJOR.MINOR.PATCH` et une logique proche de Semantic Versioning:

- `PATCH`: corrections sans changement de comportement attendu.
- `MINOR`: nouvelles fonctions compatibles.
- `MAJOR`: changements incompatibles ou migration manuelle requise.

## [0.1.0] - 2026-06-30

### Added

- Installation locale via `install.sh`.
- Installation distante via `bootstrap.sh`.
- Regle udev declenchant `veeam-usb-auto.service` sur l'UUID attendu.
- Service systemd `oneshot` pour monter le disque, lancer Veeam, attendre la fin de session, synchroniser, notifier et laisser le disque monte.
- Notifications desktop via `notify-send`.
- Desinstallation via `uninstall.sh`.
- Checks locaux via `check.sh`.
