#!/usr/bin/env bash
# Quêtes.dev — Docker, Les volumes : persistance de demo-api
# À lancer depuis la racine du repo demo-api (contient api/ et db/init.sql)
set -e

# 0. Nettoyage d'une éventuelle exécution précédente (le script est rejouable)
docker rm -f api demo-db 2>/dev/null || true
docker network rm demo_net 2>/dev/null || true
docker volume rm demo_pgdata 2>/dev/null || true

# 1. Construire l'image de l'API
docker build -t demo-api:1.0 ./api

# 2. Réseau, volume nommé et base de données
docker network create demo_net
docker volume create demo_pgdata

start_db() {
  docker run -d --name demo-db --network demo_net \
    -v demo_pgdata:/var/lib/postgresql/data \
    -v "$PWD/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
    -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
    postgres:16-alpine
  # -h localhost : teste en TCP. Pendant l'init, Postgres démarre un serveur
  # temporaire sans TCP ; sans -h, pg_isready répondrait "prêt" trop tôt.
  until docker exec demo-db pg_isready -h localhost -U demo; do sleep 1; done
}

start_db

# 3. Lancer l'API sur le même réseau et ajouter un produit
start_api() {
  docker run -d --name api --network demo_net -p 8080:3000 -e PGHOST=demo-db demo-api:1.0
  until curl -sf localhost:8080/health >/dev/null; do sleep 1; done
}

start_api
echo "--- Ajout du produit"
curl -s -X POST -H 'content-type: application/json' \
  -d '{"name":"Casquette Démo","price_cents":1200}' localhost:8080/products
echo
echo "--- GET /products (avant suppression de la base)"
curl -s localhost:8080/products
echo

# 4. Supprimer la base, la recréer sur le MÊME volume, relancer l'API
echo "--- Suppression de demo-db (le volume demo_pgdata est conservé)"
docker rm -f demo-db api
start_db
start_api
echo "--- GET /products (après recréation de la base)"
curl -s localhost:8080/products
echo

# 5. Affichage final
echo "--- docker volume ls | grep demo_pgdata"
docker volume ls | grep demo_pgdata
echo "--- GET /products final"
curl -s localhost:8080/products
echo

# Nettoyage : on supprime conteneurs et réseau, mais on GARDE le volume
docker rm -f api demo-db
docker network rm demo_net
# Pour repartir de zéro (efface les données !) :
# docker volume rm demo_pgdata
