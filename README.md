![CI](https://github.com/launeseseia/devopstp/actions/workflows/ci.yml/badge.svg)

starter-app:v1        1.64GB          421MB

starter-app:v3        226MB           54.6MB

docker pull ghcr.io/launeseseia/starter-app:latest

docker build -t starter-app:latest .

docker compose up -d

Ajout d'observabilité avec Prometheus et Grafana 
pour lancer :
docker compose --profile blue up -d --build
Prometheus port 9090
Grafana port 3000
Alert si 5 % d'erreur 
Dashboard pour debit des requetes, taux d'erreur et latence en P95
