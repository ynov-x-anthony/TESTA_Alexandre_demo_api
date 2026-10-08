set -e

docker rm -f api demo-db 2>/dev/null || true
docker network rm demo_net 2>/dev/null || true
docker volume rm demo_pgdata 2>/dev/null || true

docker build -t demo-api:1.0 ./api

docker network create demo_net
docker volume create demo_pgdata

start_db() {
  docker run -d --name demo-db --network demo_net \
    -v demo_pgdata:/var/lib/postgresql/data \
    -v "$PWD/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
    -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
    postgres:16-alpine
  until docker exec demo-db pg_isready -h localhost -U demo; do sleep 1; done
}

start_db

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

echo "--- Suppression de demo-db (le volume demo_pgdata est conservé)"
docker rm -f demo-db api
start_db
start_api
echo "--- GET /products (après recréation de la base)"
curl -s localhost:8080/products
echo

echo "--- docker volume ls | grep demo_pgdata"
docker volume ls | grep demo_pgdata
echo "--- GET /products final"
curl -s localhost:8080/products
echo

docker rm -f api demo-db
docker network rm demo_net

# Pour repartir de zéro (efface les données) :
# docker volume rm demo_pgdata
