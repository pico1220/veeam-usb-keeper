# veeam-usb-keeper

USB-triggered Veeam Agent for Linux backups with desktop notifications, monthly active fulls, and manual safe-eject workflow.

`veeam-usb-keeper` installe une regle udev et un service systemd `oneshot`.
Quand le disque USB attendu est branche, udev demarre `veeam-usb-auto.service`, qui monte le disque, lance le job Veeam, attend la fin de session, synchronise les ecritures, puis laisse le disque monte pour inspection et demontage manuel.

## Prerequis

- Linux avec `systemd` et `udev`
- Veeam Agent for Linux installe et fonctionnel
- un job Veeam deja cree
- un repository Veeam existant sur le disque USB
- une entree `/etc/fstab` permettant de monter le disque sur le point de montage choisi
- les commandes systeme suivantes : `bash`, `curl`, `tar`, `find`, `flock`, `findmnt`, `mount`, `readlink`, `sync`, `logger`, `systemctl`, `udevadm`, `awk`, `grep`, `head`, `id`
- pour les notifications bureau : `runuser`, `notify-send` et, idéalement, `loginctl` pour détecter la session graphique active

Exemple d'entree `/etc/fstab` :

```fstab
UUID=11111111-2222-3333-4444-555555555555 /backup ext4 noauto,nofail,x-systemd.automount 0 2
```

Adapte le type de systeme de fichiers (`ext4`, `xfs`, etc.) et les options selon ton disque.

## Configuration

La configuration locale n'est pas stockee dans les scripts source. L'installation charge automatiquement `config.env` s'il existe, ou un fichier donne avec `--config`. Les valeurs peuvent aussi etre passees en environnement.

Pendant l'installation, `install.sh` valide aussi l'environnement local avant de copier les fichiers: `veeamconfig` doit etre disponible, `JOB_ID` et `JOB_NAME` doivent designer le meme job Veeam, `EXPECTED_UUID` doit etre present dans `/dev/disk/by-uuid`, `/etc/fstab` doit contenir une entree pour cet UUID sur `MOUNTPOINT`, et `DESKTOP_USER` / `DESKTOP_UID` doivent correspondre a un utilisateur existant.

Depuis un clone du depot, commence par creer ta configuration locale :

```bash
cp config.env.example config.env
$EDITOR config.env
```

Variables principales :

| Variable | Obligatoire | Defaut | Role |
| --- | --- | --- | --- |
| `JOB_NAME` | oui | aucun | Nom du job Veeam a lancer avec `veeamconfig job start --name`. |
| `JOB_ID` | oui | aucun | ID du job utilise pour suivre la session dans `veeamconfig session list --jobId`. |
| `EXPECTED_UUID` | oui | aucun | UUID du disque USB attendu par la regle udev et par le script de backup. |
| `MOUNTPOINT` | oui | `/backup` | Point de montage du disque. |
| `REPO_PATH` | oui | aucun | Chemin du repository Veeam sur le disque monte. |
| `DESKTOP_USER` | oui | `$SUDO_USER` si disponible | Utilisateur qui recoit les notifications desktop. |
| `DESKTOP_UID` | oui | UID de `DESKTOP_USER` si resoluble | UID de cet utilisateur, utilise pour trouver le runtime D-Bus utilisateur. |
| `STATE_DIR` | oui | `/var/lib/veeam-usb-auto` | Stocke l'etat local, notamment le marqueur d'active full mensuel. |
| `BIN_DIR` | non | `/usr/local/bin` | Destination des scripts installes. |
| `SYSTEMD_DIR` | non | `/etc/systemd/system` | Destination du service systemd. |
| `UDEV_DIR` | non | `/etc/udev/rules.d` | Destination de la regle udev. |

Commandes utiles pour recuperer les valeurs :

```bash
lsblk -f
sudo veeamconfig job list
id -u "$USER"
```

Exemple d'entree `/etc/fstab` avec l'UUID de ton disque :

```fstab
UUID=11111111-2222-3333-4444-555555555555 /backup ext4 noauto,nofail,x-systemd.automount 0 2
```

Adapte le type de systeme de fichiers (`ext4`, `xfs`, etc.) et les options selon ton disque.

## Installation locale

Depuis un clone du depot :

```bash
git clone https://github.com/pico1220/veeam-usb-keeper.git
cd veeam-usb-keeper
cp config.env.example config.env
$EDITOR config.env
sudo ./install.sh --config config.env
```

Pour une installation ponctuelle sans fichier de configuration :

```bash
sudo \
  JOB_NAME="MonJobVeeam" \
  JOB_ID="11111111-2222-3333-4444-555555555555" \
  EXPECTED_UUID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
  MOUNTPOINT="/backup" \
  REPO_PATH="/backup/veeam/linux" \
  DESKTOP_USER="$USER" \
  DESKTOP_UID="$(id -u)" \
  ./install.sh --no-config
```

L'installation copie :

- `/usr/local/bin/veeam-usb-auto.sh`
- `/usr/local/bin/veeam-notify-desktop.sh`
- `/etc/systemd/system/veeam-usb-auto.service`
- `/etc/udev/rules.d/99-veeam-usb-auto.rules`

Elle recharge ensuite systemd et udev.

## Installation via `bootstrap.sh`

Le bootstrap telecharge une archive GitHub, la copie dans `/tmp/veeam-usb-auto-install`, puis lance `install.sh`.

Depuis une branche :

```bash
curl -fsSL -o bootstrap.sh https://raw.githubusercontent.com/pico1220/veeam-usb-keeper/main/bootstrap.sh
less bootstrap.sh

sudo \
  OWNER="pico1220" \
  REPO="veeam-usb-keeper" \
  REF="main" \
  JOB_NAME="MonJobVeeam" \
  JOB_ID="11111111-2222-3333-4444-555555555555" \
  EXPECTED_UUID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
  MOUNTPOINT="/backup" \
  REPO_PATH="/backup/veeam/linux" \
  DESKTOP_USER="$USER" \
  DESKTOP_UID="$(id -u)" \
  bash bootstrap.sh --no-config
```

Depuis un tag :

```bash
sudo OWNER="pico1220" REPO="veeam-usb-keeper" REF="v0.1.0" bash bootstrap.sh
```

`REF=main` ou `REF=master` telecharge une branche. Toute autre valeur est traitee comme un tag.

## Test manuel

Apres installation, disque branche :

```bash
sudo systemctl start veeam-usb-auto.service
sudo journalctl -u veeam-usb-auto.service -f
```

Pour tester la regle udev sans attendre un nouveau branchement :

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block --property-match=ID_FS_UUID="$EXPECTED_UUID"
```

Verifications rapides :

```bash
findmnt /backup
sudo veeamconfig session list --24
sudo systemctl status veeam-usb-auto.service
```

## Logs utiles

Service systemd :

```bash
sudo journalctl -u veeam-usb-auto.service -f
sudo journalctl -u veeam-usb-auto.service --since today
```

Messages envoyes via `logger -t veeam-usb-auto` :

```bash
sudo journalctl -t veeam-usb-auto --since today
```

Diagnostic udev :

```bash
udevadm info --query=property --name=/dev/disk/by-uuid/$EXPECTED_UUID
sudo udevadm monitor --udev --property
```

Diagnostic Veeam :

```bash
sudo veeamconfig job list
sudo veeamconfig session list --24
```

## Workflow quotidien

1. Brancher le disque USB.
2. La regle udev detecte `EXPECTED_UUID` et demarre `veeam-usb-auto.service`.
3. Le script verifie que le bon disque est monte sur `MOUNTPOINT`.
4. Si le disque est deja monte ailleurs, le montage est deplace vers `MOUNTPOINT`.
5. Si le disque n'est pas monte, le script lance `mount "$MOUNTPOINT"` via `/etc/fstab`.
6. Le script verifie que `REPO_PATH` existe.
7. Le job Veeam demarre.
8. Une fois par mois, le premier backup est lance en `--activefull`; les suivants sont incrementaux.
9. A la fin, le script lance `sync`, envoie une notification, et laisse le disque monte.
10. Inspecter le resultat si necessaire, puis demonter manuellement avant de retirer le disque.

Demontage manuel :

```bash
sync
sudo umount /backup
```

Ne retire pas le disque avant le demontage manuel : le projet est volontairement configure pour ne pas ejecter automatiquement le disque apres le backup.

## Desinstallation

Depuis le depot :

```bash
sudo ./uninstall.sh
```

Conserver l'etat local :

```bash
sudo ./uninstall.sh --keep-state
```

Supprimer aussi l'etat local :

```bash
sudo ./uninstall.sh --purge-state
```

La desinstallation arrete et desactive le service si present, supprime les scripts installes, la regle udev et l'unite systemd, puis recharge systemd et udev.
