# Rendu — Quêtes.dev, Docker étape 2 : le Dockerfile

## Liens

- Repo GitHub : https://github.com/ynov-x-anthony/TESTA_Alexandre_demo_api
- Image publiée (Docker Hub) : https://hub.docker.com/r/atesta103/demo-api (`docker pull atesta103/demo-api:1.0`)

## `docker image ls demo-api`

```
IMAGE          ID             DISK USAGE   CONTENT SIZE   EXTRA
demo-api:1.0   79105fc3add5        249MB         63.6MB
```

## `docker build ... --progress=plain` après modification d'un commentaire dans `server.js`

```
#6 [3/5] COPY package*.json ./
#6 CACHED
#7 [2/5] WORKDIR /app
#7 CACHED
#8 [4/5] RUN npm ci --omit=dev
#8 CACHED
#9 [5/5] COPY server.js db.js ./
#9 DONE 0.0s
```

Seule l'étape `COPY server.js db.js` est reconstruite : `npm ci` reste en cache.
