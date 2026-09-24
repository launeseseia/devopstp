#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${DEPLOY_DIR}/.." && pwd)"
STATE_FILE="${DEPLOY_DIR}/.active_color"
NGINX_CONF="${ROOT_DIR}/nginx/nginx.conf"

# Initialiser la couleur active par défaut si le fichier n'existe pas encore (ex: premier run CI)
if [ ! -f "$ACTIVE_FILE" ]; then
    echo "blue" > "$ACTIVE_FILE"
fi

ACTIVE=$(cat "$ACTIVE_FILE")

# Démarrer l'infrastructure de base (Redis + Nginx + conteneur actif) si elle ne tourne pas
if ! docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    echo "Démarrage initial de la pile (redis, nginx, app-${ACTIVE})..."
    docker compose --profile "$ACTIVE" up -d
    sleep 3
fi

# 1. Déterminer la version active et inactive
if [[ ! -f "$STATE_FILE" ]]; then
  echo "blue" > "$STATE_FILE"
fi

ACTIVE="$(cat "$STATE_FILE")"

if [[ "$ACTIVE" == "blue" ]]; then
  IDLE="green"
  PORT=5002
else
  IDLE="blue"
  PORT=5001
fi

echo "Déploiement en cours : ACTIVE=${ACTIVE}, IDLE=${IDLE} (port ${PORT})"

# 2. Démarrer la version inactive
docker compose -f "${ROOT_DIR}/docker-compose.yml" --profile "${IDLE}" up -d "app-${IDLE}"

# 3. Healthcheck : attente du port /health
READY=0
for _ in $(seq 1 15); do
  if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 2
done

if [[ "$READY" -ne 1 ]]; then
  echo "ÉCHEC : app-${IDLE} ne répond pas sur /health"
  echo "ROLLBACK : arrêt de app-${IDLE}, ${ACTIVE} reste actif"
  docker compose -f "${ROOT_DIR}/docker-compose.yml" --profile "${IDLE}" stop "app-${IDLE}"
  exit 1
fi

# 4. Smoke test : vérification de la couleur attendue sur /status
if ! curl -sf "http://localhost:${PORT}/status" \
  | python3 -c "import sys, json; d = json.load(sys.stdin); sys.exit(0 if d.get('deploy_color')=='${IDLE}' else 1)"; then
  echo "ÉCHEC : /status ne renvoie pas la deploy_color attendue (${IDLE})"
  echo "ROLLBACK : arrêt de app-${IDLE}, ${ACTIVE} reste actif"
  docker compose -f "${ROOT_DIR}/docker-compose.yml" --profile "${IDLE}" stop "app-${IDLE}"
  exit 1
fi

echo "Smoke test validé avec succès !"

# 5. Bascule du trafic Nginx
sed -i "s/server app-${ACTIVE}:5000;/server app-${IDLE}:5000;/" "$NGINX_CONF"
docker exec nginx-proxy nginx -s reload

# 6. Mettre à jour l'état persistant
echo "${IDLE}" > "$STATE_FILE"

# 7. Arrêter l'ancienne version
docker compose -f "${ROOT_DIR}/docker-compose.yml" --profile "${ACTIVE}" stop "app-${ACTIVE}"

echo "Bascule terminée : ${IDLE} est désormais en ligne !"
