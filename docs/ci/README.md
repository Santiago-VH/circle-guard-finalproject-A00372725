# CI/CD de CircleGuard: Jenkins, SonarQube, Playwright y deploy

Alcance acordado con el docente (proyecto individual):

| Sprint | Fases | Qué se agregó |
|--------|-------|---------------|
| Sprint 1 | Dev → Build → Test | Repositorio en GitHub, pipeline en Jenkins, validación con SonarQube |
| Sprint 2 | Test → Deploy | Pruebas E2E con Playwright, deploy simple del cliente web (local), documentación |

## 1. Qué hay en el repositorio

| Ruta | Qué es |
|------|--------|
| `Jenkinsfile` | Pipeline declarativo multibranch (main + PRs) |
| `build.gradle.kts` | JaCoCo, plugin `org.sonarqube`, separación `test` / `integrationTest` |
| `gradle/wrapper/gradle-wrapper.jar` | Wrapper de Gradle (faltaba en el código base) |
| `lombok.config` | Marca el código Lombok como `@Generated` (no cuenta en cobertura) |
| `infra/docker-compose.ci.yml` | Jenkins, SonarQube 10.7 y PostgreSQL para SonarQube |
| `infra/jenkins/` | Imagen de Jenkins: JDK 21, Docker CLI, plugins y JCasC |
| `infra/bootstrap/bootstrap-ci.sh` | Script idempotente que levanta y configura todo |
| `infra/.env.example` | Variables de referencia (el `.env` real no se versiona) |
| `CONTRIBUTING.md` | GitHub Flow, Conventional Commits, protección de `main` |
| `mobile/Dockerfile`, `mobile/nginx.conf` | Imagen del cliente web: `expo export -p web` + nginx no root (Sprint 2) |
| `tests/e2e-playwright/` | Pruebas E2E con Playwright: login, cuestionario de salud, validación de acceso (Sprint 2) |
| `deploy/compose/docker-compose.web.yml` | Ambiente dev local del cliente web, puerto 8090 (Sprint 2) |
| `deploy/scripts/deploy-web.sh`, `smoke-test.sh` | Despliegue de una versión (también rollback) y smoke test (Sprint 2) |

## 2. Etapas del pipeline

| Fase | Etapa | Qué hace |
|------|-------|----------|
| Dev | Checkout | Clona la rama o el PR (fusionado con `main`) |
| Dev | Detectar servicios modificados | En PRs compara contra `main` y elige solo los microservicios tocados. En `main` o con `FORCE_ALL` procesa los 8. Si cambia un archivo global (Gradle, Jenkinsfile) procesa todos |
| Build | Build | `./gradlew :services:<svc>:assemble` y archiva los JAR |
| Test | Pruebas unitarias + cobertura | `test` + `jacocoTestReport`; publica JUnit y cobertura JaCoCo en Jenkins |
| Test | Pruebas de integración | `integrationTest` (Testcontainers con PostgreSQL/Neo4j). Si falla, el build queda UNSTABLE |
| Test | Análisis SonarQube | `./gradlew sonar` con los XML de JaCoCo |
| Test | Quality Gate | `waitForQualityGate abortPipeline: true`: **bloqueante** |

Proyectos en SonarQube (la edición Community no analiza ramas):

- `circleguard`: solo `main`
- `circleguard-pr`: Pull Requests y demás ramas, para no mezclar el historial de `main`

### Etapas del Sprint 2 (Test → Deploy)

| Fase | Etapa | Cuándo | Qué hace |
|------|-------|--------|----------|
| Test | Imagen del cliente web | `main`, o PR que toque `mobile/`, `tests/e2e-playwright/` o `deploy/` | `docker build` de `mobile/`. Etiqueta `1.0.<build>` en `main` y `pr-<n>-<build>` en PRs, nunca `latest` |
| Test | Pruebas E2E (Playwright) | igual | Levanta la imagen recién construida en una red aislada y corre las 9 pruebas en la imagen oficial `mcr.microsoft.com/playwright`. Publica JUnit y archiva el reporte HTML. **Bloqueante** |
| Deploy | Deploy (dev local) | solo `main` | `deploy/scripts/deploy-web.sh <versión>`: Docker Compose con `up --wait` (espera el healthcheck) |
| Deploy | Smoke test | solo `main` | `deploy/scripts/smoke-test.sh`: `/health`, versión desplegada = versión del build, `/login` sirve la app y rutas principales en 200 |
| Deploy | Rollback | si falla el deploy o el smoke test | El `post { failure }` vuelve a desplegar la última versión buena (`$JENKINS_HOME/deploy/web.version`) |

El ambiente dev queda en **http://localhost:8090**.

Las pruebas E2E simulan el backend con `page.route`: verifican el comportamiento del cliente
(qué muestra, qué envía, cómo protege las rutas) de forma determinista y sin depender de los
8 servicios. Ver [tests/e2e-playwright/README.md](../../tests/e2e-playwright/README.md).

## 3. Quality Gate `CircleGuard-Gate`

| Alcance | Métrica | Falla si |
|---------|---------|----------|
| Código nuevo | Cobertura | < 60 % (meta del enunciado para servicios núcleo) |
| Código nuevo | Líneas duplicadas | > 3 % |
| Código nuevo | Calificación de confiabilidad (bugs) | peor que A |
| Código nuevo | Calificación de seguridad (vulnerabilidades) | peor que A |
| Código nuevo | Security Hotspots revisados | < 100 % |
| Código total | Calificación de seguridad | peor que A (0 vulnerabilidades) |
| Código total | Calificación de confiabilidad | peor que C |

Las condiciones sobre "código nuevo" garantizan que cada cambio entre limpio y probado
(*Clean as You Code*). Las dos condiciones sobre el código total evitan que el Quality Gate
pase vacío en el primer análisis, cuando todavía no hay código nuevo. No se exige cobertura
total ≥ 60 % porque el código base heredado no la tiene. Subirla es una historia del backlog.

Período de código nuevo: *Previous version*. El pipeline envía `sonar.projectVersion = 1.0.<BUILD_NUMBER>`.

## 4. Puesta en marcha (desde cero)

### 4.1 Requisitos

- Docker Desktop (WSL2) encendido, con al menos 6 GB de RAM asignados
- Git Bash
- Puertos 8080, 50000 y 9000 libres.
- Un **GitHub PAT (classic)** con scopes `repo` y `admin:repo_hook`

### 4.2 Levantar y configurar la plataforma

```bash
bash infra/bootstrap/bootstrap-ci.sh
```

La primera vez pide el usuario y el PAT de GitHub. El script:

1. Crea `infra/.env` con contraseñas aleatorias
2. Levanta PostgreSQL y SonarQube, cambia la contraseña de `admin`, crea los proyectos
   `circleguard` y `circleguard-pr`, el Quality Gate, el webhook SonarQube → Jenkins y un token de análisis
3. Escribe los secretos de Jenkins en `infra/.secrets/` (un archivo por clave, montado en
   `/run/secrets`), así los builds no los ven como variables de entorno
4. Construye la imagen de Jenkins y la arranca ya configurada por JCasC: usuario admin,
   credenciales `sonarqube-token` y `github-credentials`, y el servidor `SonarQube-Server`

Es idempotente: si lo vuelves a ejecutar, solo crea lo que falte. Las contraseñas quedan
en `infra/.env` (ignorado por git).

### 4.3 Proteger `main` en GitHub

GitHub → *Settings* → *Branches* → *Add branch protection rule* para `main`, con las opciones
de [CONTRIBUTING.md](../../CONTRIBUTING.md#protección-de-main-github--settings--branches--branch-protection-rule).
El check obligatorio `continuous-integration/jenkins/pr-merge` aparece en la lista
después del primer build de un PR.

### 4.4 Crear el job Multibranch en Jenkins

1. http://localhost:8080 → *New Item* → nombre `circleguard` → **Multibranch Pipeline**
2. *Branch Sources* → *Add source* → **GitHub**
   - Credentials: `github-credentials`
   - Repository HTTPS URL: `https://github.com/Santiago-VH/circle-guard-finalproject-A00372725`
   - Behaviours: *Discover branches* → "Exclude branches that are also filed as PRs";
     *Discover pull requests from origin* → "Merging the pull request with the current target branch revision"
3. *Build Configuration*: by Jenkinsfile, Script Path `Jenkinsfile`
4. *Scan Multibranch Pipeline Triggers*: ✅ Periodically if not otherwise run → **1 minute**
5. Guardar. Jenkins escanea el repo y lanza el build de `main`

### 4.5 Webhook de GitHub (opcional)

Jenkins corre en `localhost` y GitHub no puede alcanzarlo. Hay dos opciones:

- **Escaneo periódico** (paso 4.4.4): Jenkins revisa GitHub cada minuto.
- **Webhook real** con un túnel: `ngrok http 8080` y en GitHub → *Settings* → *Webhooks* →
  Payload URL `https://<id>.ngrok-free.app/github-webhook/`, content type `application/json`,
  eventos *Pushes* y *Pull requests*.

### 4.6 Actualizar Jenkins para el Sprint 2

La imagen de Jenkins ahora incluye `docker compose` (lo usa el deploy). Si ya tenías la
plataforma del Sprint 1, vuelve a correr el bootstrap para reconstruirla:
```bash
bash infra/bootstrap/bootstrap-ci.sh
```
La primera ejecución de las E2E descarga la imagen de Playwright (~2 GB).

## 5. Uso local (sin Jenkins)

```bash
./gradlew test                    # unitarias + reporte JaCoCo (build/reports/jacoco/test/html)
./gradlew integrationTest         # integración (requiere Docker)
./gradlew :services:circleguard-gateway-service:test   # un solo servicio
```

Deploy y rollback manual del cliente web (Git Bash, con la imagen ya construida):
```bash
bash deploy/scripts/deploy-web.sh 1.0.12                       # despliega esa versión
bash deploy/scripts/smoke-test.sh http://localhost:8090 1.0.12  # la verifica
docker images circleguard/web                                   # versiones disponibles para rollback
```

## 6. Problemas comunes

| Síntoma | Causa y solución |
|---------|------------------|
| SonarQube se reinicia o no llega a UP | Falta memoria o `vm.max_map_count`. En PowerShell: `wsl -d docker-desktop sysctl -w vm.max_map_count=524288` |
| `client version 1.32 is too old` en integración | Testcontainers viejo frente a Docker 29. Ya se subió a 1.21.4 |
| El Quality Gate se queda en `PENDING` | El webhook de SonarQube no llega a Jenkins. Revisa *Administration → Webhooks* (URL `http://jenkins:8080/sonarqube-webhook/`) |
| `./gradlew: Permission denied` | El pipeline hace `chmod +x`. En local: `git update-index --chmod=+x gradlew` |
| Login de Jenkins | Usuario `admin`, contraseña en `infra/.env` (`JENKINS_ADMIN_PASSWORD`) |
| `docker: 'compose' is not a docker command` en el deploy | La imagen de Jenkins es la del Sprint 1: corre de nuevo el bootstrap (4.6) |
| El deploy falla con "port is already allocated" | Algo usa el puerto 8090 en tu PC: libéralo o cambia el puerto en `deploy/compose/docker-compose.web.yml` y en la URL del smoke test |
| Las E2E tardan mucho la primera vez | Descarga de la imagen de Playwright y de `npm ci`; las siguientes usan la caché |

## 7. Evidencias para el informe del Sprint 1

- [ ] Captura del repo en GitHub con la regla de protección de `main`
- [ ] PR con el check de Jenkins en verde, fusionado con *Squash and merge*
- [ ] Jenkins: *Stage View* del job `circleguard/main` con todas las etapas en verde
- [ ] Jenkins: reporte de pruebas (JUnit) y de cobertura (JaCoCo)
- [ ] SonarQube: *Overview* de `circleguard` con el Quality Gate **Passed**
- [ ] SonarQube: definición de `CircleGuard-Gate`
- [ ] Un build en rojo por el Quality Gate (demuestra que bloquea) y el commit que lo corrige
- [ ] Salida de `bootstrap-ci.sh` (instalación desde cero con un comando)

## 8. Evidencias para el informe del Sprint 2

- [ ] Stage View de un PR que toca el cliente web: Imagen → E2E en verde (sin deploy)
- [ ] Resultado de pruebas E2E en Jenkins (9 pruebas) y el reporte HTML de Playwright archivado
- [ ] El bug del cuestionario: la prueba E2E en rojo (`responses` vacío) y luego en verde tras el arreglo
- [ ] Stage View de `main` con Deploy (dev local) y Smoke test en verde
- [ ] Log del smoke test (versión desplegada = versión del build)
- [ ] La app corriendo en http://localhost:8090 y `docker ps` con `circleguard-web`
- [ ] (Opcional) Rollback: un smoke test fallido que vuelve a la versión anterior
