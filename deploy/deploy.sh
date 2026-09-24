#!/usr/bin/env bash
set -euo pipefail

# 1. Résolution des chemins relatifs au script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ACTIVE_FILE="${SCRIPT_DIR}/.active_color"
NGINX_CONF="${PROJECT_DIR}/nginx/nginx.conf"

cd "$PROJECT_DIR"

# 2. Gestion de l'état initial (pour l'environnement éphémère de la CI)
if [ ! -f "$ACTIVE_FILE" ]; then
    echo "blue" > "$ACTIVE_FILE"
fi

ACTIVE=$(cat "$ACTIVE_FILE")

# Définition de la cible IDLE et de son port dédié
if [ "$ACTIVE" = "blue" ]; then
    IDLE="green"
    PORT=5002
else
    IDLE="blue"
    PORT=5001
fi

echo "Déploiement en cours : ACTIVE=${ACTIVE}, IDLE=${IDLE} (port ${PORT})"

# Si Nginx ne tourne pas encore (première exécution sur la machine CI), on démarre la base
if ! docker ps --format '{{.Names}}' | grep -q "nginx-proxy"; then
    echo "Démarrage initial de l'infrastructure..."
    docker compose --profile "$ACTIVE" up -d
    sleep 3
fi

# 3. Démarrage de la nouvelle version (IDLE)
docker compose --profile "$IDLE" up -d "app-${IDLE}"

# 4. Smoke test sur l'instance IDLE
echo "Attente de la disponibilité de app-${IDLE}..."
READY=0
for i in $(seq 1 10); do
    if curl -sf "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
done

if [ "$READY" -ne 1 ]; then
    echo "ÉCHEC : app-${IDLE} ne répond pas sur /health"
    echo "ROLLBACK : arrêt de app-${IDLE}, ${ACTIVE} reste actif"
    docker compose --profile "$IDLE" stop "app-${IDLE}"
    exit 1
fi

# Vérification de la couleur renvoyée par /status
STATUS_COLOR=$(curl -sf "http://127.0.0.1:${PORT}/status" | python3 -c "import sys, json; print(json.load(sys.stdin).get('deploy_color', ''))" 2>/dev/null || true)

if [ "$STATUS_COLOR" != "$IDLE" ]; then
    echo "ÉCHEC : /status ne renvoie pas la deploy_color attendue (${IDLE})"
    echo "ROLLBACK : arrêt de app-${IDLE}, ${ACTIVE} reste actif"
    docker compose --profile "$IDLE" stop "app-${IDLE}"
    exit 1
fi

echo "Smoke test validé avec succès !"

# 5. Bascule du trafic Nginx (préservation de l'inode du volume Docker)
TMP_CONF="$(mktemp)"
sed "s/server app-${ACTIVE}:5000;/server app-${IDLE}:5000;/" "$NGINX_CONF" > "$TMP_CONF"
cat "$TMP_CONF" > "$NGINX_CONF"
rm -f "$TMP_CONF"

docker exec nginx-proxy nginx -s reload

# 6. Mise à jour de l'état actif et extinction de l'ancienne version
echo "$IDLE" > "$ACTIVE_FILE"
docker compose --profile "$ACTIVE" stop "app-${ACTIVE}"

echo "Déploiement terminé avec succès. Version active : ${IDLE}"
