# Rendu — Quêtes.dev, Docker : Dockerfile et sécurité (durcir demo-api)

## Dockerfile durci (`api/Dockerfile`)

```dockerfile
FROM node:22.11-alpine

WORKDIR /app

COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --chown=node:node server.js db.js ./

USER node

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
```

## Commande `docker run` durcie

```bash
docker network create demo_net
docker run -d --name demo-db --network demo_net \
  -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
  -v "$PWD/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  postgres:16-alpine

docker run -d --name api -p 8080:3000 \
  --read-only --tmpfs /tmp:size=16m \
  --cap-drop ALL --security-opt no-new-privileges \
  --pids-limit 200 --memory 256m --cpus 1 \
  --network demo_net -e PGHOST=demo-db \
  demo-api:hardened
```

## Preuve du non-root : `docker run --rm demo-api:hardened id`

```
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
```

## `curl -s localhost:8080/health`

```
{"status":"UP"}
```

## Écriture sur le rootfs refusée

```
$ docker exec api sh -c 'touch /app/x 2>&1 || echo "rootfs read-only OK"'
touch: /app/x: Read-only file system
rootfs read-only OK
```

## `docker inspect`

```
readonly=true capdrop=[ALL]
```

## `docker ps` (healthcheck)

```
NAMES     IMAGE                STATUS
api       demo-api:hardened    Up 18 seconds (healthy)
demo-db   postgres:16-alpine   Up 4 minutes
```
