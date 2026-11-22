import { defineConfig, devices } from '@playwright/test';

/**
 * Pruebas E2E del cliente web de CircleGuard (Expo web export servido por nginx).
 *
 * - E2E_BASE_URL: dónde está el cliente web. En Jenkins es el contenedor efímero
 *   de la imagen recién construida; en local, `npx serve` sobre `expo export`.
 * - El backend se simula con page.route (ver support/api.ts), las pruebas validan el
 *   comportamiento del cliente de forma determinista, sin depender de los 8 servicios.
 */
const CI = !!process.env.CI;

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: CI,
  retries: CI ? 1 : 0,
  workers: CI ? 2 : undefined,
  timeout: 30_000,
  expect: { timeout: 10_000 },
  reporter: [
    ['list'],
    ['junit', { outputFile: 'results/junit.xml' }],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:4173',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        // Local sin navegadores de Playwright descargados: PW_CHANNEL=chrome usa el Chrome instalado
        ...(process.env.PW_CHANNEL ? { channel: process.env.PW_CHANNEL } : {}),
      },
    },
  ],
});
