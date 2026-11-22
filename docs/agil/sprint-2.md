# Sprint 2 — Test y Deploy

**Fechas:** 16-nov → 22-nov-2026
**Objetivo:** el cliente web se prueba de punta a punta con Playwright en cada PR, y cada cambio
aprobado en `main` queda desplegado automáticamente en un ambiente dev verificado por un smoke test.

## Planeación

| Historia | Pts | Estado |
|----------|-----|--------|
| HU-09 Pruebas E2E con Playwright (3 flujos) en el pipeline | 5 | |
| HU-10 Imagen Docker versionada del cliente web | 3 | |
| HU-11 Deploy simple automatizado + smoke test + rollback | 5 | |
| HU-12 Documentación final y sustentación | 3 | |
| HU-13 Bug del cuestionario (agregada en el sprint) | 2 | |
| **Total** | **18** | |

Decisiones técnicas tomadas en el sprint:

| Decisión | Motivo |
|----------|--------|
| E2E contra el cliente web con el backend simulado (`page.route`) | Pruebas deterministas del comportamiento del cliente, sin depender de LDAP, Kafka ni datos sembrados en 8 servicios |
| Validación de acceso = pase QR del estudiante + protección de rutas | El escáner de la puerta (rol staff) usa cámara y biometría, que no existen en web |
| `testID` en la pantalla del pase de acceso | Selectores estables (`getByTestId`) en vez de depender de textos repetidos |
| E2E en la imagen oficial de Playwright con `--volumes-from` | Navegadores y dependencias del sistema ya instalados; Jenkins no necesita instalarlos |
| E2E contra la imagen recién construida, en una red aislada por build | Se prueba exactamente el artefacto que luego se despliega |
| Deploy "simple" del cliente web en Docker local (puerto 8090) | El docente aceptó un deploy local; es el componente que prueban las E2E |
| Imagen etiquetada con `1.0.<build>` y `/version.txt` | Trazabilidad: el smoke test comprueba que quedó desplegada la versión correcta |
| Rollback a la última versión buena registrada en Jenkins | Si el deploy o el smoke test fallan, dev no queda roto |

Hallazgos de las pruebas E2E:
- **Bug real:** el cuestionario de salud enviaba siempre `responses: {}`. `DynamicForm` guardaba las respuestas en su estado interno y nunca se las pasaba a la pantalla. Se corrigió con un `onChange` (HU-13).
- **Bug latente:** la validación de la puerta importaba `API_BASE_URL`, que no existe en `Config.ts` (la URL quedaba `undefined`). Se cambió a `GATEWAY_BASE_URL`.

## Review

<!-- Completar después de correr el pipeline:
- Build del PR con E2E en rojo (bug del cuestionario) y luego en verde
- Build de main con Deploy + Smoke test en verde y la versión desplegada
- Puntos terminados vs comprometidos
-->

| Métrica | Valor |
|---------|-------|
| Puntos terminados / comprometidos | / 18 |
| Pruebas E2E (pasan / total) | / 9 |
| Build de `main` con deploy | # |
| Versión desplegada en dev | 1.0. |

## Retrospectiva

| ¿Qué salió bien? | ¿Qué mejorar? | Acción a futuro |
|------------------|---------------|-----------------|
| <!-- --> | <!-- --> | <!-- --> |
