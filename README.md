![CI](https://github.com/launeseseia/devopstp/actions/workflows/ci.yml/badge.svg)
starter-app:v1        1.64GB          421MB
starter-app:v3        226MB           54.6MB
docker pull ghcr.io/launeseseia/starter-app:latest
docker build -t starter-app:latest .
docker compose up -d

