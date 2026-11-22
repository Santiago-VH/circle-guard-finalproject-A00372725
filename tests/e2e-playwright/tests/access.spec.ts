import { test, expect } from '@playwright/test';
import { API, SESSION, mockBackend, startLoggedIn } from '../support/api';

/**
 * Flujo 3: validación de acceso.
 * El pase de acceso al campus es un QR firmado y de vida corta que emite el auth-service
 * (GET /api/v1/auth/qr/generate) y que el gateway-service valida en la entrada.
 * Aquí se valida el lado del cliente: solo una sesión autenticada obtiene y muestra el pase,
 * con el tiempo de expiración que define el servidor, y al cerrar sesión se pierde el acceso.
 */
test.describe('Validación de acceso', () => {
  test('sin sesión, el pase de acceso no es accesible: redirige al login', async ({ page }) => {
    await mockBackend(page);
    await page.goto('/');
    await expect(page).toHaveURL(/\/login$/);
    await expect(page.getByText('Welcome Back')).toBeVisible();
  });

  test('con sesión, pide el QR firmado al auth-service y lo muestra con su expiración', async ({ page }) => {
    await startLoggedIn(page);
    const captured = await mockBackend(page);
    await page.route(`${API.auth}/api/v1/auth/qr/generate`, (route) =>
      route.fulfill({ json: { qrToken: 'QR-E2E-TOKEN-1', expiresIn: '45' } }),
    );

    await page.goto('/');
    await expect(page.getByTestId('access-pass-status')).toContainText('ACTIVE');
    // Con el token del servidor se dibuja el QR real (no el ícono de espera)
    await expect(page.getByTestId('access-pass-qr')).toBeVisible();
    await expect(page.getByTestId('access-pass-expires')).toHaveText(/EXPIRES IN 0:4\d/);

    const qrRequest = captured.find('GET', '/api/v1/auth/qr/generate');
    expect(qrRequest, 'el pase se pide al auth-service').toBeDefined();
    expect(qrRequest!.headers()['authorization']).toBe(`Bearer ${SESSION.token}`);
  });

  test('al cerrar sesión se borra el token y se pierde el acceso al pase', async ({ page }) => {
    await startLoggedIn(page);
    await mockBackend(page);

    await page.goto('/');
    await expect(page.getByTestId('access-pass-status')).toBeVisible();

    await page.getByText('LOGOUT', { exact: true }).click();
    await expect(page).toHaveURL(/\/login$/);
    expect(await page.evaluate(() => localStorage.getItem('circleguard_token'))).toBeNull();
  });
});
