# Rendu — Quêtes.dev, Docker : Microservices et déploiement continu

## Liens

- Repo : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api (contient `notifier/`, `compose.yml` mis à jour, `.github/workflows/ci.yml` en matrix + job `deploy`)
- Run GitHub Actions **vert** (tag `v1.2.0`, jobs `image (api)`, `image (notifier)` puis `deploy`) : <À COMPLÉTER : lien du run>
- Images publiées sur GHCR :
  - `ghcr.io/ynov-x-anthony/testa_alexandre_demo_api/api:v1.2.0` : <À COMPLÉTER : lien du package>
  - `ghcr.io/ynov-x-anthony/testa_alexandre_demo_api/notifier:v1.2.0` : <À COMPLÉTER : lien du package>

> **Déploiement simulé.** Je n'ai pas de VM : le job `deploy` utilise **le runner GitHub lui-même comme machine cible** (pas de SSH). La mécanique est celle d'un vrai déploiement (login GHCR, `docker compose pull`, `docker compose up -d --no-build`, vérification de la stack), seul le transport (SSH vers un serveur) est remplacé par l'exécution locale sur le runner. Cette option est prévue par le sujet.

## 1. Architecture

```
demo-api/
├── api/            Dockerfile, Dockerfile.multi, server.js ...
├── notifier/       NOUVEAU : Dockerfile, package.json, server.js (indépendant d'api)
├── db/
└── compose.yml
```

`notifier` est un service à part entière : son propre dossier, son propre `package.json` / lockfile, son propre Dockerfile (base épinglée `node:22.23.3-alpine3.24`, multi-stage, `USER node`, `HEALTHCHECK`, CLI npm retiré) et sa propre image. `api` ne connaît de lui que son contrat réseau : `POST http://notifier:4000/notify`.

### compose.yml

- `notifier` : réseau **`back` uniquement**, **aucun `ports:`**, variable `PORT: "4000"`.
- `api` : réseaux `front` + `back` (seule passerelle), `NOTIFIER_PORT: "4000"`.
- `db`, `adminer` : réseau `back`.
- Chaque service applicatif a `build:` (dev local) **et** `image: ghcr.io/.../<service>:${TAG:-dev}` (déploiement : `docker compose pull` n'a d'effet que sur un service qui a une `image:`).

### Appel best-effort dans `api/server.js`

```js
function notifyProductCreated(product) {
  fetch(`http://notifier:${NOTIFIER_PORT}/notify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: product.name }),
    signal: AbortSignal.timeout(2000),
  }).catch((err) => console.error('[api] notify failed:', err.message));
}
```

Pas d'`await` (la réponse au client n'attend pas `notifier`), un `catch` (une promesse rejetée non gérée peut faire planter Node) et un timeout de 2 s (un `notifier` figé ne doit pas accumuler de requêtes pendantes). Le nom `notifier` est résolu par le DNS interne du réseau Compose.

## 2. Preuve locale

```
$ docker compose up -d --build
$ curl -s -i -X POST localhost:8080/products -H "Content-Type: application/json" \
    -d '{"name":"Clavier meca","price_cents":5900}'
HTTP/1.1 201 Created
{"id":5,"name":"Clavier meca","price_cents":5900,"created_at":"2026-10-27T09:00:18.189Z"}

$ docker compose logs notifier | tail -5
notifier-1  | {"level":"info","msg":"notifier started","port":4000}
notifier-1  | [notifier] nouveau produit : {"name":"Clavier meca"}
```

**Panne de `notifier`** (`docker compose stop notifier`) : `POST /products` répond toujours `201`, et `api` logge `[api] notify failed: fetch failed`. La panne d'un service secondaire ne casse pas la fonctionnalité principale.

**Isolation** : `curl localhost:4000/health` depuis l'hôte échoue (pas de `ports:`), `notifier` n'est joignable que depuis le réseau `back`.

## 3. CI : matrix `service: [api, notifier]`

Chaque service est buildé, scanné puis publié séparément :

- `api` est buildée avec `api/Dockerfile.multi` (version durcie de l'étape 8), `notifier` avec `notifier/Dockerfile`.
- **Trivy** (`CRITICAL,HIGH`, `ignore-unfixed`) : `exit-code 1` (gate bloquant) **uniquement sur les tags `v*`**, informatif (`0`) sur les branches.
- **Push** (tags seulement) : on re-tague (`docker tag`) et on pousse **l'image déjà scannée**, au lieu de refaire un build, pour que l'image publiée soit exactement celle que Trivy a validée.
- Le nom d'image est passé en minuscules (`${GITHUB_REPOSITORY,,}`) : GHCR refuse les majuscules, or le repo s'appelle `TESTA_Alexandre_demo_api`.
- Chaque image est taguée avec le tag Git (`v1.2.0`) et porte le label `org.opencontainers.image.source` (lien package ↔ repo).

## 4. Job `deploy`

`needs: image` + `if: startsWith(github.ref, 'refs/tags/v')` : il ne tourne qu'après les deux jobs de la matrix, et seulement sur un tag. Étapes : login GHCR → génération du `.env` et d'un secret `db_password` jetable → `docker compose pull api notifier` → `docker compose up -d --no-build` → vérification (`/health`, `POST /products`, présence de la notification dans les logs de `notifier`).

`--no-build` garantit qu'on déploie l'image pull depuis le registre, jamais une image reconstruite localement.

Extrait de la vérification dans le run : <À COMPLÉTER : coller les lignes `[notifier] nouveau produit : {"name":"Deploy check"}` du log du run>

## Réponses aux critères d'acceptation

| Critère | Où |
|---|---|
| notifier : Dockerfile propre, pas de port publié, réseau `back` seul | `notifier/Dockerfile`, `compose.yml` |
| `api` appelle `notifier` par son nom, en best-effort | `api/server.js` (`notifyProductCreated`), test avec `notifier` arrêté → `201` |
| CI : deux images séparées taguées avec la version Git | job `image` (matrix) |
| Job de déploiement sur tag, run vert | job `deploy` (simulé sur le runner) |
