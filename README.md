# veeam-usb-keeper
USB-triggered Veeam Agent for Linux backups with desktop notifications, monthly active fulls, and manual safe-eject workflow.

## Requirements

- Linux with systemd and udev
- Veeam Agent for Linux

## Install

```bash
curl -fsSL -o bootstrap.sh https://raw.githubusercontent.com/pico1220/veeam-usb-keeper/main/bootstrap.sh
less bootstrap.sh
sudo OWNER=<OWNER> REPO=veeam-plugvault REF=v0.1.0 bash bootstrap.sh