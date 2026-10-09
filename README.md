# demo-api

Mini API « catalogue » (Node + Express + PostgreSQL), conteneurisée et orchestrée avec Docker Compose. Fil rouge des quêtes Docker.

La stack se compose de trois services :

| Service | Image | Rôle | Accès |
|---|---|---|---|
| `api` | construite depuis `./api` | API REST (`/health`, `/products`) | http://localhost:8080 |
| `db` | `postgres:16-alpine` | base de données, volume `pgdata` | réseau interne uniquement (aucun port publié) |
| `adminer` | `adminer:4` | client SQL web | http://localhost:8081 |

## Prérequis

- Docker avec Compose v2 (`docker compose version`)
- Windows : travailler depuis WSL (bind mount de `db/init.sql`)

## Démarrage

```bash
cp .env.example .env                                   # variables non sensibles
mkdir -p secrets
openssl rand -hex 16 > secrets/db_password.txt         # mot de passe de la base (hors Git)
docker compose up -d --build
```

Le mot de passe n'est ni dans `.env` ni dans `compose.yml` : il passe par **Docker Secrets** (`secrets/db_password.txt`, monté dans `/run/secrets/db_password`). Le service `db` le lit via `POSTGRES_PASSWORD_FILE` ; le service `api` le lit au démarrage et l'exporte en `PGPASSWORD`, sans modifier le code applicatif.

`.env` et `secrets/` sont ignorés par Git. Seul `.env.example` est commité.

## Vérifier

```bash
docker compose ps
curl -s localhost:8080/health
curl -s localhost:8080/products
curl -s -X POST -H 'content-type: application/json' \
  -d '{"name":"Gourde","price_cents":900}' localhost:8080/products
```

Adminer : http://localhost:8081 (système : PostgreSQL, serveur : `db`, utilisateur et base : valeurs de `.env`, mot de passe : contenu de `secrets/db_password.txt`).

Commande testée : `docker compose up -d --build`. Extrait de `docker compose ps` :

```
NAME                 IMAGE                COMMAND                  SERVICE   STATUS                    PORTS
demo-api-adminer-1   adminer:4            "entrypoint.sh docke…"   adminer   Up 20 seconds             0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
demo-api-api-1       demo-api-api         "sh -c 'export PGPAS…"   api       Up 15 seconds (healthy)   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp
demo-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        Up 20 seconds (healthy)   5432/tcp
```

## Persistance

Les données vivent dans le volume nommé `pgdata`. `docker compose down` supprime les conteneurs et le réseau mais **garde les volumes** : après un `down` puis un `up`, les produits ajoutés sont toujours là (testé avec « Gourde »).

## Arrêter et repartir de zéro

```bash
docker compose down        # arrête et supprime les conteneurs, GARDE les données
docker compose down -v     # supprime aussi le volume pgdata : données perdues, init.sql rejoué
```

`init.sql` n'est joué qu'au tout premier démarrage de la base (volume vide). Après `down -v`, il est rejoué.

## Variables (`.env`)

| Variable | Rôle | Défaut |
|---|---|---|
| `POSTGRES_USER` | utilisateur PostgreSQL | `demo` |
| `POSTGRES_DB` | nom de la base | `demo` |
| `API_PORT` | port hôte de l'API | `8080` |
| `ADMINER_PORT` | port hôte d'Adminer | `8081` |
