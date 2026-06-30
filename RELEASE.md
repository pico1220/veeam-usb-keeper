# Release

Convention de version:

- La version source est dans `VERSION`.
- Les tags publics sont au format `vMAJOR.MINOR.PATCH`, par exemple `v0.1.0`.
- `CHANGELOG.md` doit contenir une entree datee pour chaque tag publie.
- La commande d'installation stable du README doit pointer vers le dernier tag publie.

Checklist de release:

1. Mettre a jour `VERSION`.
2. Mettre a jour `PROJECT_VERSION` dans `bootstrap.sh`.
3. Mettre a jour `CHANGELOG.md`.
4. Mettre a jour les exemples epingles dans `README.md`.
5. Lancer les checks:

```bash
./check.sh
```

6. Committer:

```bash
git add VERSION CHANGELOG.md RELEASE.md README.md bootstrap.sh
git commit -m "Release vX.Y.Z"
```

7. Tagger:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin main
git push origin vX.Y.Z
```

Commande d'installation stable attendue apres publication:

```bash
curl -fsSL https://raw.githubusercontent.com/pico1220/veeam-usb-keeper/vX.Y.Z/bootstrap.sh -o bootstrap.sh
sudo bash bootstrap.sh --config config.env
```
