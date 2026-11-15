#!/usr/bin/env bash
# bootstrap-ci.sh — Levanta y configura la plataforma de CI de CircleGuard
#   Jenkins (JCasC) + SonarQube (+ PostgreSQL) con Docker Compose.
#
# Idempotente: se puede ejecutar cuantas veces se quiera; solo crea lo que falta.
#   - Crea infra/.env (contraseñas aleatorias, pide el PAT de GitHub)
#   - Levanta SonarQube y lo configura por API, contraseña admin, proyectos,
#     Quality Gate "CircleGuard-Gate", webhook a Jenkins y token de análisis
#   - Escribe los secretos de Jenkins en infra/.secrets (uno por archivo)
#   - Construye y levanta Jenkins ya configurado (credenciales + servidor Sonar)
#
# Uso (Git Bash en Windows, o Linux/macOS), desde la raíz del repo:
#   bash infra/bootstrap/bootstrap-ci.sh
# Requisitos: docker (con compose v2) y curl.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$INFRA_DIR/.env"
COMPOSE=(docker compose -f "$INFRA_DIR/docker-compose.ci.yml" --env-file "$ENV_FILE")

SONAR_URL="${SONAR_URL:-http://localhost:9000}"
GATE_NAME="CircleGuard-Gate"
PROJECTS=("circleguard:CircleGuard" "circleguard-pr:CircleGuard (Pull Requests)")
TOKEN_NAME="jenkins-ci"
WEBHOOK_NAME="Jenkins"
WEBHOOK_URL="http://jenkins:8080/sonarqube-webhook/"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker no está instalado / no está en el PATH"
command -v curl   >/dev/null || die "curl no está instalado"
docker info >/dev/null 2>&1 || die "Docker no responde. ¿Docker Desktop está abierto?"

# ---------------------------------------------------------------- .env helpers
get_env() { grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- || true; }
set_env() {
  local key="$1" val="$2"
  if grep -qE "^$key=" "$ENV_FILE"; then
    # | como separador: los valores generados no lo contienen
    sed -i "s|^$key=.*|$key=$val|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$val" >> "$ENV_FILE"
  fi
}
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${1:-20}"; }

# ------------------------------------------------------------------- 1) .env
if [[ ! -f "$ENV_FILE" ]]; then
  cp "$INFRA_DIR/.env.example" "$ENV_FILE"
  log "Creado infra/.env a partir de .env.example"
fi
[[ -n "$(get_env JENKINS_ADMIN_USER)" ]]     || set_env JENKINS_ADMIN_USER admin
[[ -n "$(get_env JENKINS_LOCATION_URL)" ]]   || set_env JENKINS_LOCATION_URL "http://localhost:8080/"
[[ -n "$(get_env JENKINS_ADMIN_PASSWORD)" ]] || set_env JENKINS_ADMIN_PASSWORD "$(rand 20)"
[[ -n "$(get_env SONAR_DB_PASSWORD)" ]]      || set_env SONAR_DB_PASSWORD "$(rand 24)"
# SonarQube 10 exige: >=12 caracteres, mayúscula, minúscula, dígito y símbolo
[[ -n "$(get_env SONAR_ADMIN_PASSWORD)" ]]   || set_env SONAR_ADMIN_PASSWORD "Cg-$(rand 16)-9a!"

if [[ -z "$(get_env GITHUB_USER)" ]]; then
  read -r -p "Usuario de GitHub: " gh_user; set_env GITHUB_USER "$gh_user"
fi
if [[ -z "$(get_env GITHUB_TOKEN)" ]]; then
  read -r -s -p "GitHub PAT (classic, scopes repo + admin:repo_hook): " gh_token; echo
  set_env GITHUB_TOKEN "$gh_token"
fi
SONAR_ADMIN_PASSWORD="$(get_env SONAR_ADMIN_PASSWORD)"
ok ".env listo"

# ------------------------------------------------------------ 2) SonarQube up
log "Levantando SonarQube y su base de datos..."
"${COMPOSE[@]}" up -d sonar-db sonarqube

log "Esperando a que SonarQube esté UP (puede tardar 1-3 min la primera vez)..."
for i in $(seq 1 90); do
  if [[ "$(curl -fs "$SONAR_URL/api/system/status" 2>/dev/null || true)" == *'"status":"UP"'* ]]; then
    ok "SonarQube UP"; break
  fi
  [[ $i -eq 90 ]] && die "SonarQube no arrancó. Revisa: docker logs cg-sonarqube"
  sleep 5
done

# --------------------------------------------------------- 3) Sonar: admin pwd
api() { # api METHOD PATH [curl args...]  (autenticado como admin; muestra el error de SonarQube)
  local method="$1" path="$2" out code body; shift 2
  out="$(curl -sS -u "admin:$SONAR_ADMIN_PASSWORD" -X "$method" -w $'\n%{http_code}' "$SONAR_URL$path" "$@")" \
    || die "No se pudo conectar a SonarQube ($method $path)"
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [[ "$code" -ge 400 ]]; then
    die "SonarQube respondió HTTP $code en $method $path: $body"
  fi
  printf '%s' "$body"
}
api_ok() { # api_ok METHOD PATH [args]: true si SonarQube responde 2xx (sin abortar)
  local method="$1" path="$2"; shift 2
  curl -fs -o /dev/null -u "admin:$SONAR_ADMIN_PASSWORD" -X "$method" "$SONAR_URL$path" "$@"
}

if [[ "$(curl -fs -u admin:admin "$SONAR_URL/api/authentication/validate" || true)" == *'"valid":true'* ]]; then
  log "Cambiando la contraseña por defecto de admin..."
  curl -fsS -u admin:admin -X POST "$SONAR_URL/api/users/change_password" \
    --data-urlencode "login=admin" \
    --data-urlencode "previousPassword=admin" \
    --data-urlencode "password=$SONAR_ADMIN_PASSWORD" >/dev/null
fi
[[ "$(api GET /api/authentication/validate || true)" == *'"valid":true'* ]] \
  || die "No se pudo autenticar en SonarQube con SONAR_ADMIN_PASSWORD de infra/.env"
ok "Admin de SonarQube autenticado"

# ------------------------------------------------------------ 4) Proyectos
for entry in "${PROJECTS[@]}"; do
  key="${entry%%:*}"; name="${entry#*:}"
  if [[ "$(api GET "/api/projects/search?projects=$key")" == *"\"key\":\"$key\""* ]]; then
    ok "Proyecto $key ya existe"
  else
    api POST /api/projects/create --data-urlencode "project=$key" \
      --data-urlencode "name=$name" --data-urlencode "mainBranch=main" >/dev/null
    ok "Proyecto $key creado"
  fi
done

# ---------------------------------------------------------- 5) Quality Gate
# Condiciones (documentadas en docs/ci/README.md):
#   Código nuevo : cobertura < 60 %, duplicación > 3 %, confiabilidad peor que A,
#                  seguridad peor que A, hotspots revisados < 100 %
#   Código total : seguridad peor que A (0 vulnerabilidades),
#                  confiabilidad peor que C
if api_ok GET "/api/qualitygates/show?name=$GATE_NAME"; then
  ok "Quality Gate $GATE_NAME ya existe"
else
  api POST /api/qualitygates/create --data-urlencode "name=$GATE_NAME" >/dev/null
  ok "Quality Gate $GATE_NAME creado"
fi
# Cada condición se agrega solo si falta (idempotente aunque una ejecución anterior se haya cortado)
gate_json="$(api GET "/api/qualitygates/show?name=$GATE_NAME")"
add_cond() {
  if [[ "$gate_json" == *"\"metric\":\"$1\""* ]]; then return 0; fi
  api POST /api/qualitygates/create_condition --data-urlencode "gateName=$GATE_NAME" \
    --data-urlencode "metric=$1" --data-urlencode "op=$2" --data-urlencode "error=$3" >/dev/null
  ok "Condición agregada: $1 $2 $3"
}
add_cond new_coverage                    LT 60
add_cond new_duplicated_lines_density    GT 3
add_cond new_reliability_rating          GT 1
add_cond new_security_rating             GT 1
add_cond new_security_hotspots_reviewed  LT 100
add_cond security_rating                 GT 1
add_cond reliability_rating              GT 3
ok "Condiciones del Quality Gate verificadas"
for entry in "${PROJECTS[@]}"; do
  key="${entry%%:*}"
  api POST /api/qualitygates/select --data-urlencode "gateName=$GATE_NAME" \
    --data-urlencode "projectKey=$key" >/dev/null
done
ok "Quality Gate asociado a los proyectos"

# ---------------------------------------------------------- 6) Webhook
if [[ "$(api GET /api/webhooks/list)" == *"\"name\":\"$WEBHOOK_NAME\""* ]]; then
  ok "Webhook $WEBHOOK_NAME ya existe"
else
  api POST /api/webhooks/create --data-urlencode "name=$WEBHOOK_NAME" \
    --data-urlencode "url=$WEBHOOK_URL" >/dev/null
  ok "Webhook SonarQube -> Jenkins creado"
fi

# ---------------------------------------------------------- 7) Token
if [[ -z "$(get_env SONAR_TOKEN)" ]]; then
  api_ok POST /api/user_tokens/revoke --data-urlencode "name=$TOKEN_NAME" || true
  token_json="$(api POST /api/user_tokens/generate --data-urlencode "name=$TOKEN_NAME" \
                  --data-urlencode "type=GLOBAL_ANALYSIS_TOKEN")"
  token="$(printf '%s' "$token_json" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
  [[ -n "$token" ]] || die "No se pudo generar el token de SonarQube: $token_json"
  set_env SONAR_TOKEN "$token"
  ok "Token de análisis generado y guardado en infra/.env"
else
  ok "SONAR_TOKEN ya existe en infra/.env"
fi

# ---------------------------------------------------------- 8) Jenkins
# Secretos para JCasC: un archivo por clave en infra/.secrets (montado en /run/secrets)
SECRETS_DIR="$INFRA_DIR/.secrets"
mkdir -p "$SECRETS_DIR"
for key in JENKINS_ADMIN_USER JENKINS_ADMIN_PASSWORD JENKINS_LOCATION_URL GITHUB_USER GITHUB_TOKEN SONAR_TOKEN; do
  printf '%s' "$(get_env "$key")" > "$SECRETS_DIR/$key"
done
chmod 600 "$SECRETS_DIR"/* 2>/dev/null || true
ok "Secretos de Jenkins escritos en infra/.secrets"

log "Construyendo y levantando Jenkins (JCasC)..."
"${COMPOSE[@]}" up -d --build --force-recreate jenkins

log "Esperando a Jenkins..."
for i in $(seq 1 60); do
  code="$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/login || true)"
  [[ "$code" == "200" ]] && { ok "Jenkins UP"; break; }
  [[ $i -eq 60 ]] && die "Jenkins no arrancó. Revisa: docker logs cg-jenkins"
  sleep 5
done

cat <<EOF

==============================================================================
 Plataforma de CI lista
   Jenkins   : http://localhost:8080   usuario: $(get_env JENKINS_ADMIN_USER)
   SonarQube : $SONAR_URL   usuario: admin
   Contraseñas: en infra/.env (no se versiona)

 Siguiente paso: crear el job Multibranch "circleguard" (docs/ci/README.md, paso 4)
==============================================================================
EOF
