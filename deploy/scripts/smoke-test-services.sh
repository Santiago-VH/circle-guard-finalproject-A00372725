#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# smoke-test-services.sh — Verifica el backend desplegado.
#  1) Cada microservicio responde HTTP en su puerto (cualquier código < 500).
#  2) Flujo real: login de staff_guard en auth -> auth pide el anonymousId a identity
#     -> devuelve un JWT. Prueba auth + identity + Postgres juntos.
# Uso: deploy/scripts/smoke-test-services.sh [host]     (por defecto: localhost)
# -----------------------------------------------------------------------------
set -euo pipefail
HOST="${1:-localhost}"
fail=0

check() { # nombre puerto ruta
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://$HOST:$2$3" || echo 000)
  if [[ "$code" != 000 && "$code" -lt 500 ]]; then echo "OK   $1 ($2) -> HTTP $code"
  else echo "FAIL $1 ($2) -> HTTP $code"; fail=1; fi
}

check identity  8083 /api/v1/identities/map
check promotion 8088 /api/v1/circles/user/00000000-0000-0000-0000-000000000000
check form      8086 /api/v1/questionnaires/active
check gateway   8087 /api/v1/gate/validate

resp=$(curl -s --max-time 30 -X POST "http://$HOST:8180/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"username":"staff_guard","password":"password"}' || true)
if echo "$resp" | grep -q '"token"'; then echo "OK   login staff_guard (auth -> identity) devuelve JWT"
else echo "FAIL login staff_guard -> $resp"; fail=1; fi

[[ $fail -eq 0 ]] && echo "Smoke test del backend: OK" || { echo "Smoke test del backend: FALLÓ" >&2; exit 1; }
