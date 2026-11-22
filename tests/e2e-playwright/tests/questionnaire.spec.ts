import { test, expect } from '@playwright/test';
import { API, SESSION, mockBackend, startLoggedIn } from '../support/api';

/**
 * Flujo 2: cuestionario de salud (form-service).
 *   GET  /api/v1/questionnaires/active  -> preguntas dinámicas
 *   POST /api/v1/surveys                -> respuestas del estudiante
 */
const QUESTIONNAIRE = {
  id: 'q-2026-11',
  title: 'Daily Health Check',
  description: 'Answer before coming to campus',
  questions: [
    { id: 'fever', text: 'Do you have fever?', type: 'YES_NO' },
    { id: 'symptom', text: 'Main symptom', type: 'SINGLE_CHOICE', options: JSON.stringify(['None', 'Cough', 'Headache']) },
    { id: 'notes', text: 'Anything else?', type: 'TEXT' },
  ],
};

test.describe('Cuestionario de salud', () => {
  test.beforeEach(async ({ page }) => {
    await startLoggedIn(page);
  });

  test('responde el cuestionario y envía las respuestas al form-service', async ({ page }) => {
    const captured = await mockBackend(page);
    await page.route(`${API.form}/api/v1/questionnaires/active`, (route) =>
      route.fulfill({ json: QUESTIONNAIRE }),
    );
    await page.route(`${API.form}/api/v1/surveys`, (route) => route.fulfill({ status: 201, json: { id: 's-1' } }));

    await page.goto('/questionnaire');
    await expect(page.getByText('Daily Health Check')).toBeVisible();
    await expect(page.getByText('Do you have fever?')).toBeVisible();

    await page.getByText('NO', { exact: true }).click();
    await page.getByText('Cough', { exact: true }).click();
    await page.getByPlaceholder('Type your response...').fill('Mild cough since yesterday');
    await page.getByText('SUBMIT REPORT', { exact: true }).click();

    // Vuelve al inicio tras enviar
    await expect(page).toHaveURL(/\/$/);

    const survey = captured.find('POST', '/api/v1/surveys');
    expect(survey, 'el cliente debe enviar la encuesta').toBeDefined();
    const body = survey!.postDataJSON();
    expect(body.anonymousId).toBe(SESSION.anonymousId);
    expect(body.responses).toEqual({
      fever: 'NO',
      symptom: 'Cough',
      notes: 'Mild cough since yesterday',
    });
  });

  test('sin cuestionario activo: informa al usuario', async ({ page }) => {
    await mockBackend(page);
    await page.route(`${API.form}/api/v1/questionnaires/active`, (route) =>
      route.fulfill({ status: 404, json: { message: 'No active questionnaire' } }),
    );

    await page.goto('/questionnaire');
    await expect(page.getByText('No active health survey available.')).toBeVisible();
  });

  test('si el envío falla, se queda en el cuestionario', async ({ page }) => {
    await mockBackend(page);
    await page.route(`${API.form}/api/v1/questionnaires/active`, (route) =>
      route.fulfill({ json: QUESTIONNAIRE }),
    );
    await page.route(`${API.form}/api/v1/surveys`, (route) => route.fulfill({ status: 500, json: {} }));

    await page.goto('/questionnaire');
    await page.getByText('YES', { exact: true }).click();
    await page.getByText('SUBMIT REPORT', { exact: true }).click();

    await expect(page).toHaveURL(/\/questionnaire$/);
    await expect(page.getByText('SUBMIT REPORT', { exact: true })).toBeVisible();
  });
});
