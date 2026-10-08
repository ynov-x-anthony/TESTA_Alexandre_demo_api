# Rendu — Quêtes.dev, Docker : Builds multi-étapes et gestion des secrets

Fichiers dans le repo `demo-api` : `api/Dockerfile.naive` (repère de comparaison, pas le Dockerfile de prod) et `api/Dockerfile.multi`.

## `api/Dockerfile.naive`

```dockerfile
FROM node:22
WORKDIR /app
COPY . .
RUN npm ci
CMD ["node", "server.js"]
```

## `api/Dockerfile.multi`

```dockerfile

FROM node:22.11-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci --omit=dev

FROM node:22.11-alpine AS runtime
WORKDIR /app
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js db.js package.json ./
USER node
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
```

## Comparaison de taille : `docker image ls demo-api`

```
IMAGE               ID             DISK USAGE   CONTENT SIZE   EXTRA
demo-api:multi      1b0efa2cd27d        225MB           55MB
demo-api:naive      bc6d3a8db0ea       1.64GB          404MB
```

| | naive | multi | ratio |
|---|---|---|---|
| Taille disque | 1.64 GB | 225 MB | ~7,3× |
| Contenu compressé | 404 MB | 55 MB | ~7,3× |

`demo-api:multi` est environ 7× plus petit que `demo-api:naive` (objectif : ≥ 2×).

## Preuve que le secret ne fuit pas

Faux token : `//registry.example.com/:_authToken=FAKE-123` dans un fichier `fake.npmrc` hors du `$HOME`.

```
$ docker build -f api/Dockerfile.multi --secret id=npmrc,src=fake.npmrc -t demo-api:multi ./api
... naming to docker.io/library/demo-api:multi done

$ docker history --no-trunc demo-api:multi | grep -i FAKE-123
(aucune ligne)

$ docker run --rm --user root demo-api:multi sh -c 'cat /root/.npmrc 2>&1'
cat: can't open '/root/.npmrc': No such file or directory
```

## L'image tourne toujours

```
$ docker run --rm -d --name api-multi -p 8081:3000 demo-api:multi
$ curl -s localhost:8081/health
{"status":"UP"}

$ docker ps  →  api-multi   Up 18 seconds (healthy)

$ docker run --rm demo-api:multi id
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
```

(Port 8081 utilisé car 8080 était occupé par le conteneur `api` de l'étape précédente.)
