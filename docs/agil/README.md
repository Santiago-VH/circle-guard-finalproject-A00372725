# Gestión ágil de CircleGuard

## Marco de trabajo: Scrum adaptado a un equipo de una persona

Se usa **Scrum** con sprints de una semana, alineados con las entregas que fijó el docente:

| Sprint | Fechas | Objetivo (alcance acordado con el docente) |
|--------|--------|--------------------------------------------|
| Sprint 0 | hasta 8-nov-2026 | Preparación: repositorio, marco ágil, branching, backlog |
| Sprint 1 | 9-nov → 15-nov-2026 | Fases **Dev, Build, Test**: GitHub, pipeline Jenkins, SonarQube |
| Sprint 2 | 16-nov → 22-nov-2026 | Fases **Test y Deploy**: E2E con Playwright, deploy simple, documentación |

**¿Por qué Scrum y no Kanban?** Las entregas tienen fechas fijas y un alcance cerrado por
iteración, que es justo lo que ordena Scrum. El estudiante es *Product Owner* y *Developer*, el docente actúa como *stakeholder* en la
*review*. Se mantienen los eventos que aportan valor a una persona: planeación, *review* y
retrospectiva escritas. La *daily* se reemplaza por el tablero actualizado.

Tablero: **GitHub Projects** (vista Board con columnas *Backlog → Sprint → In progress → In review → Done*).
Cada historia es un issue creado con la plantilla `.github/ISSUE_TEMPLATE/historia-de-usuario.md`
y cada PR la cierra con `Closes #N`.

## Backlog del producto (fases Dev → Deploy)

| ID | Historia | Sprint | Pts |
|----|----------|--------|-----|
| HU-01 | Repositorio con estrategia de ramas y `main` protegida | 0 | 2 |
| HU-02 | Tablero ágil con backlog y criterios de aceptación | 0 | 1 |
| HU-03 | Build reproducible del monorepo con Gradle Wrapper | 1 | 2 |
| HU-04 | Plataforma de CI (Jenkins + SonarQube) reproducible con un comando | 1 | 5 |
| HU-05 | Pipeline multibranch con build y pruebas por servicio | 1 | 5 |
| HU-06 | Cobertura de pruebas medida con JaCoCo | 1 | 2 |
| HU-07 | Quality Gate de SonarQube que bloquea cambios | 1 | 3 |
| HU-08 | Pruebas de integración separadas de las unitarias | 1 | 2 |
| HU-09 | Pruebas E2E con Playwright sobre el cliente web | 2 | 5 |
| HU-10 | Imagen Docker versionada del cliente web | 2 | 3 |
| HU-11 | Despliegue simple automatizado desde el pipeline | 2 | 5 |
| HU-12 | Documentación final y sustentación | 2 | 3 |
| HU-13 | Corregir el envío de respuestas del cuestionario (bug hallado por E2E) | 2 | 2 |

### Criterios de aceptación (Sprint 0 y Sprint 1)

**HU-01 — Branching.** *Como desarrollador quiero un flujo de ramas definido para que `main` esté siempre estable.*
- Dado `CONTRIBUTING.md`, cuando alguien lo lee, entonces conoce GitHub Flow, los prefijos de rama y Conventional Commits.
- Dado un push directo a `main`, cuando se intenta, entonces GitHub lo rechaza (regla de protección).
- Dado un PR, cuando el check de Jenkins no está en verde, entonces no se puede fusionar.

**HU-02 — Tablero.** *Como Product Owner quiero un tablero con el backlog para planear los sprints.*
- El tablero de GitHub Projects tiene las 12 historias, cada una con criterios de aceptación y sprint asignado.

**HU-03 — Build reproducible.** *Como desarrollador quiero compilar con `./gradlew` sin instalar Gradle.*
- Dado un clon limpio, cuando ejecuto `./gradlew assemble`, entonces compilan los 8 microservicios.
- `gradle-wrapper.jar` está versionado y `gradlew` tiene permiso de ejecución en git.

**HU-04 — Plataforma de CI.** *Como equipo de plataforma quiero levantar Jenkins y SonarQube con un comando para no depender de pasos manuales.*
- Dado un equipo con Docker, cuando ejecuto `bash infra/bootstrap/bootstrap-ci.sh`, entonces Jenkins (:8080) y SonarQube (:9000) quedan arriba y configurados.
- Ejecutarlo dos veces no duplica proyectos, gates, webhooks ni tokens (idempotente).
- Ningún secreto queda versionado en el repositorio.

**HU-05 — Pipeline.** *Como desarrollador quiero que cada PR se construya y pruebe solo para saber si mi cambio rompe algo.*
- Dado un PR que solo toca `gateway-service`, cuando corre el pipeline, entonces solo se construye y prueba ese servicio.
- Dado un push a `main`, cuando corre el pipeline, entonces se procesan los 8 servicios.
- Jenkins reporta el estado del build como check en el PR.

**HU-06 — Cobertura.** *Como líder técnico quiero medir la cobertura para saber qué tan probado está el código.*
- Cada build publica el reporte JaCoCo por servicio en Jenkins y lo envía a SonarQube.

**HU-07 — Quality Gate.** *Como líder técnico quiero que el código que no cumple calidad no llegue a `main`.*
- Dado un cambio con cobertura de código nuevo < 60 % o con una vulnerabilidad, cuando corre el pipeline, entonces la etapa *Quality Gate* falla y el PR queda bloqueado.
- Evidencia de al menos un build bloqueado y su corrección.

**HU-08 — Pruebas de integración.** *Como desarrollador quiero separar las pruebas que requieren Docker para que las unitarias sean rápidas.*
- `./gradlew test` no ejecuta pruebas con `@Tag("integration")`; `./gradlew integrationTest` solo ejecuta esas.
- El pipeline publica ambos reportes por separado.

### Criterios de aceptación (Sprint 2)

**HU-09 — Pruebas E2E.** *Como equipo quiero probar los flujos principales del cliente web de punta a punta para detectar errores que las pruebas unitarias no ven.*
- Hay al menos 3 flujos automatizados con Playwright: inicio de sesión, cuestionario de salud y validación de acceso.
- Las pruebas corren en el pipeline en cada PR que toque el cliente web y bloquean el merge si fallan.
- Jenkins publica el resultado (JUnit) y archiva el reporte HTML de Playwright.

**HU-10 — Imagen del cliente web.** *Como equipo de plataforma quiero una imagen inmutable del cliente web para desplegar exactamente lo que se probó.*
- `docker build` multi-stage (`expo export -p web` + nginx), usuario no root, healthcheck.
- La imagen se etiqueta con la versión del build (`1.0.<n>`), nunca `latest`, y expone `/version.txt`.

**HU-11 — Deploy simple.** *Como equipo quiero que cada cambio aprobado en `main` quede desplegado sin pasos manuales.*
- Tras Quality Gate y E2E en verde, `main` despliega en el ambiente dev local (http://localhost:8090).
- Un smoke test verifica que responde, que la versión desplegada es la del build y que `/login` sirve la app.
- Si el deploy o el smoke test fallan, el pipeline vuelve a la última versión buena (rollback).

**HU-12 — Documentación.** *Como docente quiero poder reproducir y evaluar el proyecto.*
- Guía de puesta en marcha, diagramas del pipeline, sprints con review y retrospectiva, e informe de cada sprint con su registro de IAG.

**HU-13 — Bug del cuestionario.** *Como estudiante quiero que mis respuestas lleguen al form-service.*
- Dado un cuestionario respondido, cuando lo envío, entonces el `POST /api/v1/surveys` contiene mis respuestas (antes llegaba `{}`).
- La prueba E2E del cuestionario lo verifica.

Detalle de cada sprint: [sprint-0.md](sprint-0.md) · [sprint-1.md](sprint-1.md) · [sprint-2.md](sprint-2.md)
