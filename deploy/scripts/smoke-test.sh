#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# smoke-test.sh — Verifica que el cliente web desplegado responde y es la versión esperada.
# Uso: deploy/scripts/smoke-test.sh <url-base> <version-esperada>
#   deploy/scripts/smoke-test.sh http://host.docker.internal:8090 1.0.42
# Sale con código distinto de 0 si algo falla (el pipeline hace rollback).
# -----------------------------------------------------------------------------
set -euo pipefail

BASE_URL="${1:?Uso: smoke-test.sh <url-base> <version-esperada>}"
EXPECTED_VERSION="${2:?Uso: smoke-test.sh <url-base> <version-esperada>}"
RETRIES="${SMOKE_RETRIES:-15}"

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

# 1) El servicio responde (con reintentos mientras arranca)
for i in $(seq 1 "$RETRIES"); do
  if [[ "$(curl -fsS "$BASE_URL/health" 2>/dev/null || true)" == ok* ]]; then
    echo "OK  /health responde"
    break
  fi
  [[ $i -eq $RETRIES ]] && fail "/health no respondió tras $RETRIES intentos"
  sleep 2
done

# 2) Es la versión que se acaba de desplegar
deployed="$(curl -fsS "$BASE_URL/version.txt" | tr -d '[:space:]')"
[[ "$deployed" == "$EXPECTED_VERSION" ]] \
  || fail "versión desplegada '$deployed', se esperaba '$EXPECTED_VERSION'"
echo "OK  versión desplegada: $deployed"

# 3) Las rutas principales sirven la app (login es la puerta de entrada)
login_html="$(curl -fsS "$BASE_URL/login")"
[[ "$login_html" == *"Welcome Back"* ]] || fail "/login no contiene la pantalla de inicio de sesión"
echo "OK  /login sirve la pantalla de inicio de sesión"

for path in /questionnaire /; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL$path")"
  [[ "$code" == "200" ]] || fail "$path respondió HTTP $code"
  echo "OK  $path -> 200"
done

echo "Smoke test superado: circleguard-web $deployed"
