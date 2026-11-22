# Pruebas E2E del cliente web (Playwright)

Tres flujos del cliente web de CircleGuard, con el backend simulado (`page.route`):

| Archivo | Flujo | Casos |
|---|---|---|
| `tests/login.spec.ts` | Inicio de sesión | credenciales válidas (guarda sesión y entra), inválidas (error 401), campos vacíos |
| `tests/questionnaire.spec.ts` | Cuestionario de salud | responde y envía las respuestas, sin cuestionario activo, error al enviar |
| `tests/access.spec.ts` | Validación de acceso | sin sesión no hay pase, el pase QR se pide con el token y muestra su expiración, logout quita el acceso |

`support/api.ts` intercepta todas las llamadas a los microservicios (`localhost:8082…8180`),
responde lo que cada prueba necesita y guarda las peticiones para verificar qué envió el cliente.

## En Jenkins
La etapa **Pruebas E2E (Playwright)** levanta la imagen recién construida del cliente web
(`circleguard/web:<versión>`) en una red aislada y corre estas pruebas en la imagen oficial
`mcr.microsoft.com/playwright`. Publica `results/junit.xml` y archiva el reporte HTML.

## En local
```bash
# 1) Cliente web: compilar y servir
cd mobile && npx expo export -p web --output-dir dist && npx serve -l 4173 dist
# 2) Pruebas (otra terminal)
cd tests/e2e-playwright
npm ci
npx playwright install chromium     # la primera vez
npx playwright test                 # E2E_BASE_URL=http://localhost:4173 por defecto
npx playwright show-report
```
Para probar contra el despliegue de dev: `E2E_BASE_URL=http://localhost:8090 npx playwright test`.
