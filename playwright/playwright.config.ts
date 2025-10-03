import { defineConfig, devices } from '@playwright/test'
import path from 'path'

// Create constants mapping to our storage files
export const STORAGE_STATE = path.join(__dirname, 'storageState.json')
export const ADMIN_STORAGE_STATE = path.join(
  __dirname,
  'adminStorageState.json',
)

/**
 * @see https://playwright.dev/docs/test-configuration
 * @type {import('@playwright/test').PlaywrightTestConfig}
 */
export default defineConfig({
  testDir: './tests',
  /* Maximum time one test can run for (default 30s). */
  timeout: 60 * 1000,
  expect: {
    /**
     * Maximum time expect() should wait for the condition to be met.
     * (default 5s)
     * For example in `await expect(locator).toHaveText();`
     */
    timeout: 10000,
  },
  /* Maximum time for the entire test run. Since we run the entire suite
     on each browser separately this should be enough. */
  globalTimeout: 60 * 60 * 1000,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Retry once on CI */
  retries: process.env.CI ? 1 : 0,
  /* Allows multiple tests from each file to be run at the same time */
  fullyParallel: true,
  workers: process.env.WORKERS
    ? parseInt(process.env.WORKERS) // Use explicit worker count if given
    : process.env.CI
      ? 3 // Otherwise use 3 on CI/CD
      : undefined, // and a bunch locally (seems to be 7, but the default isn't documented)
  /* Reporter to use. See https://playwright.dev/docs/test-reporters */
  reporter: process.env.CI ? 'github' : 'list',
  /* Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions. */
  use: {
    /* Tell the browser to slow everything down for debugging
    launchOptions: {
      slowMo: 100,
    }, */
    /* Maximum time each action such as `click()` can take. Defaults to 0 (no limit). */
    actionTimeout: 0,
    /* Base URL to use in actions like `await page.goto('/')`. */
    baseURL: 'http://localhost:2900',
    /* Collect trace when retrying the failed test. See https://playwright.dev/docs/trace-viewer */
    trace: process.env.CI ? 'on-first-retry' : 'on',
    screenshot: 'only-on-failure',
    viewport: { width: 1600, height: 1200 },
  },

  projects: [
    {
      name: 'keycloak',
      testMatch: /keycloak.setup\.ts/,
    },
    {
      name: 'setup',
      testMatch: /global.setup\.ts/,
    },
    // {
    //   name: 'admin-chromium',
    //   testMatch: '**/admin/**',
    //   dependencies: ['setup'],
    //   use: {
    //     ...devices['Desktop Chrome'],
    //     storageState: ADMIN_STORAGE_STATE,
    //   },
    // },
    {
      name: 'chromium',
      // testIgnore: '**/admin/**',
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: STORAGE_STATE,
        viewport: { width: 1600, height: 1200 },
      },
    },
    {
      name: 'firefox',
      use: {
        ...devices['Desktop Firefox'],
        storageState: STORAGE_STATE,
        viewport: { width: 1600, height: 1200 },
      },
      dependencies: ['setup'],
    },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    //   dependencies: ['setup'],
    // },
  ],
})
