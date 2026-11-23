#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# deploy-services.sh — Construye y despliega el backend (middleware + 5 servicios)
# en el ambiente dev local (proyecto compose "circleguard-backend").
# Uso: deploy/scripts/deploy-services.sh [version]      (por defecto: dev)
# Requiere los bootJar ya generados:  ./gradlew bootJar -x test
# -----------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:-dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/deploy/compose/docker-compose.services.yml")

for svc in auth identity promotion form gateway; do
  ls "$ROOT"/services/circleguard-$svc-service/build/libs/*-SNAPSHOT.jar > /dev/null 2>&1 \
    || { echo "Falta el jar de $svc. Ejecuta primero: ./gradlew bootJar -x test" >&2; exit 1; }
done

echo "Desplegando backend CircleGuard (versión $VERSION)..."
SERVICES_VERSION="$VERSION" "${COMPOSE[@]}" up -d --build --wait --wait-timeout 300
SERVICES_VERSION="$VERSION" "${COMPOSE[@]}" ps
echo "Backend desplegado: auth:8180 identity:8083 promotion:8088 form:8086 gateway:8087"
