#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# deploy-web.sh — Despliega una versión del cliente web en el ambiente dev local.
# Uso: deploy/scripts/deploy-web.sh <version>
#   deploy/scripts/deploy-web.sh 1.0.42      # despliega circleguard/web:1.0.42
# También sirve para rollback manual: deploy-web.sh <version-anterior>
# La imagen debe existir en el Docker local (la construye el pipeline).
# -----------------------------------------------------------------------------
set -euo pipefail

VERSION="${1:?Uso: deploy-web.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

docker image inspect "circleguard/web:$VERSION" > /dev/null 2>&1 \
  || { echo "No existe la imagen circleguard/web:$VERSION" >&2; exit 1; }

echo "Desplegando circleguard/web:$VERSION en dev (http://localhost:8090)..."
WEB_VERSION="$VERSION" docker compose -p circleguard-dev \
  -f "$ROOT/deploy/compose/docker-compose.web.yml" up -d --wait --wait-timeout 90
echo "Desplegado: circleguard/web:$VERSION"
