# Rendu — Quêtes.dev, Docker : Compose (la stack demo-api)

Contient `compose.yml`, `.env.example`, `.gitignore` (qui exclut `.env` et `secrets/`) et `README.md`.

## `compose.yml`

```yaml
services:
  api:
    build: ./api
    entrypoint:
      - sh
      - -c
      - export PGPASSWORD="$$(cat /run/secrets/db_password)" && exec node server.js
    environment:
      PGHOST: db
      PGUSER: ${POSTGRES_USER}
      PGDATABASE: ${POSTGRES_DB}
    secrets:
      - db_password
    ports:
      - "${API_PORT:-8080}:3000"
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 5s
      timeout: 3s
      retries: 10
    restart: unless-stopped

  adminer:
    image: adminer:4
    ports:
      - "${ADMINER_PORT:-8081}:8080"
    depends_on:
      - db
    restart: unless-stopped

volumes:
  pgdata:

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

## `.env.example`

```
POSTGRES_USER=demo
POSTGRES_DB=demo
API_PORT=8080
ADMINER_PORT=8081
```

Le mot de passe de la base n'est pas dans `.env` : il passe par Docker Secrets (`secrets/db_password.txt`, ignoré par Git).

## Commande testée et `docker compose ps`

```
$ docker compose up -d --build

$ docker compose ps
NAME                 IMAGE                COMMAND                  SERVICE   STATUS                    PORTS
demo-api-adminer-1   adminer:4            "entrypoint.sh docke…"   adminer   Up 20 seconds             0.0.0.0:8081->8080/tcp, [::]:8081->8080/tcp
demo-api-api-1       demo-api-api         "sh -c 'export PGPAS…"   api       Up 15 seconds (healthy)   0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp
demo-api-db-1        postgres:16-alpine   "docker-entrypoint.s…"   db        Up 20 seconds (healthy)   5432/tcp
```

## Vérifications

```
$ curl -s localhost:8080/products
[{"id":3,"name":"T-shirt conteneur","price_cents":1990,...},{"id":2,"name":"Mug Docker","price_cents":990,...},{"id":1,"name":"Sticker Demo","price_cents":150,...}]

$ curl -s -X POST -H 'content-type: application/json' -d '{"name":"Gourde","price_cents":900}' localhost:8080/products
{"id":4,"name":"Gourde","price_cents":900,"created_at":"2026-10-09T06:50:07.422Z"}

$ docker compose down
 Container demo-api-db-1 Removed
 Network demo-api_default Removed

$ docker compose up -d
 Container demo-api-db-1 Healthy
 Container demo-api-api-1 Started

$ curl -s localhost:8080/products
[{"id":4,"name":"Gourde","price_cents":900,"created_at":"2026-10-09T06:50:07.422Z"},{"id":3,...},{"id":2,...},{"id":1,...}]

$ curl -s -o /dev/null -w "HTTP %{http_code}\n" localhost:8081      # Adminer
HTTP 200
```

« Gourde » survit à `docker compose down` puis `up` : le volume `pgdata` est conservé.

## Gestion des secrets (bonus)

- `db` : `POSTGRES_PASSWORD_FILE=/run/secrets/db_password` (mécanisme standard de l'image postgres).
- `api` : `db.js` ne lit que `PGPASSWORD`. Un `entrypoint` lit le secret au démarrage et l'exporte, sans modifier le code applicatif.
- Aucun mot de passe en clair dans l'environnement des conteneurs : `printenv` et `docker inspect` ne montrent que `POSTGRES_PASSWORD_FILE=/run/secrets/db_password`.
- `.env` et `secrets/` sont ignorés par Git (`git status --ignored` les marque `!!`) ; seul `.env.example` est commité.
