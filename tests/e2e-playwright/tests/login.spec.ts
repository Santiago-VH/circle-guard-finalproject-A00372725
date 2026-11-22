import { test, expect } from '@playwright/test';
import { API, SESSION, mockBackend } from '../support/api';

/**
 * Flujo 1: inicio de sesión (auth-service, POST /api/v1/auth/login).
 */
test.describe('Inicio de sesión', () => {
  test('credenciales válidas: guarda la sesión y entra al pase de acceso', async ({ page }) => {
    const captured = await mockBackend(page);
    await page.route(`${API.auth}/api/v1/auth/login`, (route) =>
      route.fulfill({ json: { token: SESSION.token, anonymousId: SESSION.anonymousId } }),
    );

    await page.goto('/login');
    await page.getByPlaceholder('Username').fill('health_user');
    await page.getByPlaceholder('Password').fill('S3cret!');
    await page.getByText('SIGN IN', { exact: true }).click();

    // Redirige al inicio y muestra el pase de acceso
    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByTestId('access-pass-status').first()).toContainText('ACTIVE');

    // Envió las credenciales al auth-service
    const login = captured.find('POST', '/api/v1/auth/login');
    expect(login, 'el cliente debe llamar al auth-service').toBeDefined();
    expect(login!.postDataJSON()).toEqual({ username: 'health_user', password: 'S3cret!' });

    // La sesión queda persistida
    const stored = await page.evaluate(() => ({
      id: localStorage.getItem('circleguard_anon_id'),
      token: localStorage.getItem('circleguard_token'),
    }));
    expect(stored).toEqual({ id: SESSION.anonymousId, token: SESSION.token });
  });

  test('credenciales inválidas: muestra el error y no inicia sesión', async ({ page }) => {
    await mockBackend(page);
    await page.route(`${API.auth}/api/v1/auth/login`, (route) =>
      route.fulfill({ status: 401, json: { message: 'Invalid credentials' } }),
    );

    await page.goto('/login');
    await page.getByPlaceholder('Username').fill('health_user');
    await page.getByPlaceholder('Password').fill('wrong');

    // En web el login muestra el error con window.alert
    const alerts: string[] = [];
    page.on('dialog', async (dialog) => {
      alerts.push(dialog.message());
      await dialog.dismiss();
    });
    await page.getByText('SIGN IN', { exact: true }).click();
    await expect.poll(() => alerts.join(' | ')).toContain('[401] Invalid credentials');

    await expect(page).toHaveURL(/\/login$/);
    expect(await page.evaluate(() => localStorage.getItem('circleguard_token'))).toBeNull();
  });

  test('campos vacíos: no llama al backend', async ({ page }) => {
    const captured = await mockBackend(page);
    await page.goto('/login');
    await page.getByText('SIGN IN', { exact: true }).click();

    await expect(page).toHaveURL(/\/login$/);
    expect(captured.find('POST', '/api/v1/auth/login')).toBeUndefined();
  });
});
