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
  // Maximum time one test can run for (default 30s)
  timeout: 60 * 1000,
  expect: {
    // Maximum time expect() should wait for the condition to be met.
    // For example in `await expect(locator).toHaveText();`
    timeout: 10000,
  },
  // Maximum time for the entire test run. Since we run the entire suite
  // on each browser separately this should be enough.
  globalTimeout: 60 * 60 * 1000,
  // Fail the build on CI if you accidentally left test.only in the source code.
  forbidOnly: !!process.env.CI,
  // Retry on CI. The full COSMOS stack and the browsers share one runner, so a
  // momentarily starved JS event loop (seen in traces as "Stale connection:
  // Nms without pings") can freeze a page long enough to time out a single
  // action. One retry lets a test ride out a transient freeze; a second retry
  // mostly just multiplied the cost of genuinely broken tests until the run
  // hit globalTimeout and got killed before finishing.
  retries: process.env.CI ? 1 : 0,
  // Allows multiple tests from each file to be run at the same time
  fullyParallel: true,
  workers: process.env.WORKERS
    ? parseInt(process.env.WORKERS) // Use explicit worker count if given
    : process.env.CI
      ? 2
      : '50%', // Otherwise use 2 on CI/CD. The COSMOS Docker stack runs on the same
  // runner as the browsers; 3 workers starved the event loop and caused the
  // data-viewer/docs streaming tests to time out (see retries note), use half locally
  // Reporter to use. See https://playwright.dev/docs/test-reporters
  reporter: process.env.CI ? 'github' : 'list',
  // Shared settings for all the projects below. See https://playwright.dev/docs/api/class-testoptions.
  use: {
    // Tell the browser to slow everything down for debugging
    // launchOptions: {
    //   slowMo: 100,
    // },
    // Maximum time each action such as `click()` can take. Defaults to 0 (no
    // limit), which let a single click on a frozen page consume the entire test
    // timeout with an opaque "Test timeout exceeded" error. A finite cap makes a
    // stuck action fail fast with a clear message and hand off to a retry.
    actionTimeout: 30 * 1000,
    // Base URL to use in actions like `await page.goto('/')`
    baseURL: 'http://localhost:2900',
    // Keep the trace of every failed attempt, not just retries: with
    // 'on-first-retry' a test that fails then passes leaves a trace of the
    // *passing* run, which is the one that needs no diagnosing.
    // See https://playwright.dev/docs/trace-viewer
    trace: process.env.CI ? 'retain-on-failure' : 'on',
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
      // The enterprise specs have their own project below. Without this the core
      // test:parallel glob picks them up now that they use the same .p.spec.ts
      // naming, running them with fullyParallel: true (which breaks their
      // ordered chains) on top of the dedicated enterprise batches.
      testIgnore: '**/enterprise/**',
      dependencies: ['setup'],
      use: {
        ...devices['Desktop Chrome'],
        storageState: STORAGE_STATE,
        viewport: { width: 1600, height: 1200 },
      },
    },
    {
      name: 'enterprise',
      testMatch: '**/enterprise/**',
      // Parallelize across files but NOT within a file. Most enterprise specs
      // are ordered chains (autonomic is explicit about it) that depend on state
      // left by the previous test in the same file, so only whole files are safe
      // to run concurrently. Files that mutate scope-wide singletons still can't
      // overlap at all and run in the separate serial batch (see package.json).
      fullyParallel: false,
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
