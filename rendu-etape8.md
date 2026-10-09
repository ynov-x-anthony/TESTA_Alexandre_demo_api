# Rendu — Quêtes.dev, Docker : Analyse de vulnérabilité avec Trivy

## Liens

- Repo : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api (contient `.github/workflows/ci.yml` et `api/Dockerfile.multi`)
- Run GitHub Actions **rouge** (tag `v1.1.1`, régression volontaire, base `node:22.11-alpine`) : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api/actions/runs/37905276401
  - échoue à l'étape **Scan Trivy (gate)** : `Total: 21 (HIGH: 19, CRITICAL: 2)` sur `alpine 3.20.3`, `exit code 1` (le même commit sur `main` : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api/actions/runs/37905274338)
- Run GitHub Actions **vert** (tag `v1.1.2`, base corrigée `node:22.23.3-alpine3.24`) : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api/actions/runs/37905281441
  - le même commit sur `main` : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api/actions/runs/37905279342

Les runs plus anciens (tag `v1.0.0` et les premiers commits) sont rouges pour une autre raison : la référence `aquasecurity/trivy-action@0.28.0` du cours n'existe pas (le tag est `v0.28.0`), le job s'arrêtait avant le build. Corrigé en épinglant l'action sur le SHA de `v0.36.0`.

## Scan avant : `trivy image --severity HIGH,CRITICAL demo-api:multi` (`scan-avant.txt`)

Image construite avec `node:22.11-alpine`.

```
demo-api:multi (alpine 3.20.3)
Total: 21 (HIGH: 19, CRITICAL: 2)
  libcrypto3 / libssl3 : CVE-2026-31789 (CRITICAL), CVE-2024-12797, CVE-2025-15467, CVE-2025-69421,
                         CVE-2026-28387..28390 (HIGH)   installé 3.3.2-r0  -> corrigé en 3.3.7-r0
  musl / musl-utils    : CVE-2025-26519, CVE-2026-40200  (1.2.5-r0 -> 1.2.5-r3)
  zlib                 : CVE-2026-22184                  (1.3.1-r1 -> 1.3.2-r0)

Node.js (node-pkg)
Total: 33 (HIGH: 30, CRITICAL: 3)
  app/node_modules/proxy-addr     : CVE-2026-90711 (CRITICAL)  2.0.7 -> 2.0.8      <- dépendance de l'application
  usr/local/lib/node_modules/npm/ : 32 CVE (tar, brace-expansion, minimatch, glob, cross-spawn,
                                    pacote, sigstore, ip-address, http-cache-semantics)  <- CLI npm fourni avec l'image node
```

Trivy signale aussi : « This OS version is no longer supported by the distribution (alpine 3.20.3) ».

**Total avant : 54 CVE HIGH/CRITICAL** (21 OS + 33 dépendances).

## Corrections

| Cause | Correction |
|---|---|
| Base Alpine 3.20 en fin de vie, paquets OS vulnérables | `node:22.11-alpine` -> `node:22.23.3-alpine3.24` (tag toujours épinglé), dans les deux étages de `Dockerfile.multi` |
| `proxy-addr` 2.0.7 (dépendance d'Express) | `npm audit fix --package-lock-only` dans `api/` -> `proxy-addr` 2.0.8, `npm audit` : 0 vulnérabilité, `package.json` inchangé |
| 32 CVE dans le CLI `npm` embarqué dans l'image `node` (même dans la dernière image Node 22) | `RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx` dans l'étage `runtime` : `npm` ne sert pas à lancer `node server.js` |

Remarque : le `rm` ne réduit pas la taille de l'image, les fichiers restent dans le layer de l'image de base. Ils ne sont plus dans le système de fichiers final et ne sont plus vus par Trivy.

## Scan après : `trivy image --severity HIGH,CRITICAL --ignore-unfixed demo-api:multi` (`scan-apres.txt`)

```
Report Summary
│ demo-api:multi (alpine 3.24.2)                 │ alpine   │ 0 │ - │
│ app/node_modules/...  (toutes les dépendances) │ node-pkg │ 0 │ - │
│ opt/yarn-v1.22.22/package.json                 │ node-pkg │ 0 │ - │
│ usr/local/lib/node_modules/corepack/package.json │ node-pkg │ 0 │ - │
```

Aucun `Total:` : plus aucune vulnérabilité. Même résultat **sans** `--ignore-unfixed` (inventaire complet) : **0 CVE HIGH/CRITICAL**.

| | Avant | Après |
|---|---|---|
| OS (Alpine) | 21 | 0 |
| Dépendances | 33 | 0 |
| **Total HIGH/CRITICAL** | **54** | **0** |

Vérification que l'image fonctionne toujours :

```
$ curl -s localhost:8082/health
{"status":"UP"}
$ docker run --rm demo-api:multi id
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
```

## CI : `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: ["**"]
    tags: ["v*"]

permissions:
  contents: read

jobs:
  build-and-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build (local, pour scanner)
        uses: docker/build-push-action@v6
        with:
          context: ./api
          file: ./api/Dockerfile.multi
          load: true
          tags: demo-api:ci

      - name: Scan Trivy (gate)
        uses: aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0
        with:
          image-ref: demo-api:ci
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: "1" # la CI échoue si une CVE HIGH/CRITICAL corrigeable est trouvée
          format: table
```

`exit-code: "1"` transforme le scan en gate : un push ou un tag qui réintroduit une CVE HIGH/CRITICAL corrigeable fait échouer le job.
