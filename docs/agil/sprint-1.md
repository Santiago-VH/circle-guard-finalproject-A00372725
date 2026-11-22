# Sprint 1 — Dev, Build y Test

**Fechas:** 9-nov → 15-nov-2026
**Objetivo:** cada cambio que llega a `main` está compilado, probado y validado por SonarQube
de forma automática, a través de un PR con un pipeline de Jenkins que bloquea si algo falla.

## Planeación

| Historia | Pts | Estado |
|----------|-----|--------|
| HU-03 Build reproducible con Gradle Wrapper | 2 | |
| HU-04 Plataforma de CI con un comando | 5 | |
| HU-05 Pipeline multibranch por servicio | 5 | |
| HU-06 Cobertura con JaCoCo | 2 | |
| HU-07 Quality Gate bloqueante | 3 | |
| HU-08 Pruebas de integración separadas | 2 | |
| **Total comprometido** | **19** | |

Decisiones técnicas tomadas en el sprint:

| Decisión | Motivo |
|----------|--------|
| Jenkins y SonarQube en Docker Compose local, configurados por script + JCasC | Reproducible con un comando; sin costo de nube para el alcance de este sprint |
| SonarQube 10.7 Community + PostgreSQL | Versión usada en el curso; PostgreSQL en vez de H2 para persistir el historial |
| Proyectos `circleguard` (main) y `circleguard-pr` (PRs) | Community no tiene análisis por rama; así el historial de `main` no se contamina |
| Quality Gate sobre código nuevo (cobertura ≥ 60 %) + seguridad/confiabilidad total | Exigir calidad a lo nuevo sin bloquear por la deuda heredada |
| Ejecución selectiva por servicio en PRs, completa en `main` | Feedback rápido en PRs y análisis completo en `main` |
| `@Tag("integration")` + tarea `integrationTest` | Las unitarias no dependen de Docker; las de integración usan Testcontainers |
| Testcontainers 1.19.3 → 1.21.4 | La versión anterior no funciona con Docker Engine 29 (Docker Desktop actual) |
| Versionar `gradle-wrapper.jar` | El `.gitignore` original ignoraba `*.jar` y `./gradlew` no podía arrancar |
| Secretos de Jenkins como archivos (`/run/secrets`) y no como variables de entorno | Los builds no pueden leer los tokens con `env` |

## Review

Sustentado ante el docente. Se completaron las 6 historias comprometidas: el pipeline corre de
punta a punta y `main` quedó en verde con el Quality Gate en *Passed*.

| Métrica | Valor |
|---------|-------|
| Puntos terminados / comprometidos | 19 / 19 |
| PRs fusionados | 2 (#1 pipeline, #2 ajuste de IdentityClient y Sonar en PRs selectivos) |
| Builds de PR-1 hasta quedar en verde | 5 (1 rojo por pruebas, 2 rojos por Quality Gate, 1 inestable por integración, 1 verde) |
| Quality Gate de `main` | Passed: seguridad A, confiabilidad A, mantenibilidad A |
| Cobertura total (SonarQube) | 31,3 % |
| Pruebas de integración | 7 (Testcontainers con Neo4j, PostgreSQL y Redis), en verde |

Problemas resueltos durante el sprint: `gradle-wrapper.jar` sin versionar, 3 pruebas rotas del código
base, 2 bugs BLOCKER de transacciones, condiciones por defecto del Quality Gate en SonarQube 10.7,
Testcontainers incompatible con Docker 29 y Sonar en PRs selectivos. Detalle en el informe del Sprint 1.

| ¿Qué salió bien? | ¿Qué mejorar? | Acción para el Sprint 2 |
|------------------|---------------|-------------------------|
| El Quality Gate y las pruebas detectaron problemas reales antes de llegar a `main` | El primer build real llegó tarde (el día de la entrega): los problemas aparecieron todos juntos | Correr el pipeline en cuanto exista la primera versión de cada etapa |
| La plataforma se levanta con un comando y es idempotente | Commits agrupados ("fixes(...)") en lugar de uno por cambio | Un commit por corrección, con Conventional Commits |
| Ejecución selectiva por servicio en PRs | Supuestos sin verificar (gate de Sonar vacío, versión de Testcontainers) | Verificar en local antes de subir (`gradlew test`, `integrationTest`) |
