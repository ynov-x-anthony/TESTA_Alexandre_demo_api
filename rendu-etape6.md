# Rendu — Quêtes.dev, Docker : Les réseaux (isoler la base derrière l'API)

Script : `reseaux_alexandre_testa.sh` (à la racine du repo `demo-api`).

## Script

```bash
#!/usr/bin/env bash
# Quêtes.dev — Docker, Les réseaux : isoler la base derrière l'API
# À lancer depuis la racine du repo demo-api (contient api/ et db/init.sql)
set -e

cleanup() {
  # -v : supprime aussi le volume anonyme créé par l'image postgres
  docker rm -fv demo-api demo-db 2>/dev/null || true
  docker network rm demo_front demo_back 2>/dev/null || true
}

# 0. Nettoyage d'une exécution précédente
cleanup

# 1. Construire l'image de l'API
docker build -q -t demo-api:1.0 ./api

# 2. Deux réseaux personnalisés (jamais le bridge par défaut)
docker network create demo_front
docker network create demo_back

# 3. La base : demo_back uniquement, aucun -p
docker run -d --name demo-db --network demo_back \
  -v "$PWD/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
  postgres:16-alpine
# -h localhost : teste en TCP, sinon pg_isready répond "prêt" pendant l'init
until docker exec demo-db pg_isready -h localhost -U demo; do sleep 1; done

# 4. L'API : démarre sur demo_back, puis rejoint demo_front. Publiée sur 8080
docker run -d --name demo-api --network demo_back -p 8080:3000 \
  -e PGHOST=demo-db demo-api:1.0
docker network connect demo_front demo-api
until curl -sf localhost:8080/health >/dev/null; do sleep 1; done

# 5. Vérifications
echo
echo "=== 1. demo-api résout demo-db par son nom"
docker exec demo-api getent hosts demo-db

echo
echo "=== 2. Un conteneur tiers sur demo_front seulement ne joint PAS demo-db"
docker run --rm --network demo_front alpine nc -zv -w 3 demo-db 5432 \
  || echo "ÉCHEC (attendu) : aucun réseau commun avec demo-db"

echo
echo "=== 3. Adresses IPv4 par réseau"
for c in demo-db demo-api; do
  echo "[$c]"
  docker inspect -f '{{range $net, $v := .NetworkSettings.Networks}}  {{$net}}: {{$v.IPAddress}}{{"\n"}}{{end}}' "$c"
done

echo "=== 4. Ports publiés"
docker ps --filter name=demo- --format '{{.Names}}\t{{.Ports}}'

echo
echo "=== 5. curl localhost:8080/products"
curl -s localhost:8080/products
echo

# 6. Nettoyage final
cleanup
```

## Exécution (build et pull d'`alpine` omis)

```
localhost:5432 - no response
localhost:5432 - accepting connections

=== 1. demo-api résout demo-db par son nom
172.23.0.2        demo-db  demo-db

=== 2. Un conteneur tiers sur demo_front seulement ne joint PAS demo-db
nc: bad address 'demo-db'
ÉCHEC (attendu) : aucun réseau commun avec demo-db

=== 3. Adresses IPv4 par réseau
[demo-db]
  demo_back: 172.23.0.2

[demo-api]
  demo_back: 172.23.0.3
  demo_front: 172.22.0.2

=== 4. Ports publiés
demo-api	0.0.0.0:8080->3000/tcp, [::]:8080->3000/tcp
demo-db	5432/tcp

=== 5. curl localhost:8080/products
[{"id":3,"name":"T-shirt conteneur","price_cents":1990,"created_at":"2026-10-08T13:23:46.028Z"},{"id":2,"name":"Mug Docker","price_cents":990,"created_at":"2026-10-08T13:23:46.028Z"},{"id":1,"name":"Sticker Demo","price_cents":150,"created_at":"2026-10-08T13:23:46.028Z"}]
```

## Lecture

- **Résolution par nom** : `demo-api` joint `demo-db` via le DNS du réseau `demo_back` (172.23.0.2).
- **Isolation** : le conteneur tiers, branché seulement sur `demo_front`, n'a aucun réseau commun avec `demo-db` : son nom n'est même pas résolu (`bad address`).
- **Réseaux** : `demo-db` est sur `demo_back` uniquement ; `demo-api` est sur `demo_back` et `demo_front`. Le bridge par défaut n'est pas utilisé.
- **Ports** : seul `demo-api` est publié (8080). `demo-db` n'a aucun port publié (`5432/tcp` est seulement le port déclaré par l'image, sans correspondance sur l'hôte).
