import { Page, Request } from '@playwright/test';

/**
 * Backend simulado para las pruebas E2E.
 *
 * El cliente web llama a los microservicios en localhost:<puerto> (mobile/constants/Config.ts).
 * Aquí se interceptan esas llamadas con page.route para que cada prueba controle exactamente
 * qué responde el backend y pueda inspeccionar lo que el cliente envió.
 */
export const API = {
  auth: 'http://localhost:8180',
  form: 'http://localhost:8086',
  promotion: 'http://localhost:8088',
};

export const SESSION = {
  anonymousId: 'anon-e2e-001',
  token: 'e2e.jwt.token',
};

const BACKEND = /^http:\/\/localhost:(8082|8083|8084|8085|8086|8087|8088|8180)\//;

/** Peticiones capturadas, para verificar qué envió el cliente. */
export class CapturedRequests {
  readonly all: Request[] = [];
  find(method: string, path: string): Request | undefined {
    return this.all.find((r) => r.method() === method && new URL(r.url()).pathname === path);
  }
}

/**
 * Respuestas por defecto de todos los servicios. Cada prueba puede registrar después
 * sus propias rutas: Playwright usa la última registrada que coincida.
 */
export async function mockBackend(page: Page): Promise<CapturedRequests> {
  const captured = new CapturedRequests();
  // Se registran TODAS las llamadas al backend, también las que responde una ruta propia de la prueba
  page.on('request', (request) => {
    if (BACKEND.test(request.url())) captured.all.push(request);
  });
  await page.route(BACKEND, async (route) => {
    const { pathname } = new URL(route.request().url());

    if (pathname === '/api/v1/auth/qr/generate') {
      return route.fulfill({ json: { qrToken: 'QR-E2E-TOKEN-1', expiresIn: '45' } });
    }
    if (pathname.startsWith('/api/v1/mesh/stats/')) {
      return route.fulfill({ json: { confirmedCount: 0, unconfirmedCount: 0 } });
    }
    return route.fulfill({ json: {} });
  });
  return captured;
}

/** Deja una sesión iniciada en localStorage antes de cargar la app (como haría el login). */
export async function startLoggedIn(page: Page): Promise<void> {
  await page.addInitScript(({ anonymousId, token }) => {
    window.localStorage.setItem('circleguard_anon_id', anonymousId);
    window.localStorage.setItem('circleguard_token', token);
  }, SESSION);
}
