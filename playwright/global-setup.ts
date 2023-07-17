// global-setup.ts
import { chromium, FullConfig } from '@playwright/test'

async function globalSetup(config: FullConfig) {
  const { baseURL } = config.projects[0].use
  const browser = await chromium.launch()
  const page = await browser.newPage()

  await page.goto(`${baseURL}/tools/cmdtlmserver`)
  await new Promise((resolve) => setTimeout(resolve, 500))
  if (process.env.ENTERPRISE === '1') {
    await page.locator('input[name="username"]').fill('operator')
    await page.locator('input[name="password"]').fill('operator')
    await page.locator('input:has-text("Sign In")').click()
    await page.waitForURL(`${baseURL}/tools/cmdtlmserver`)
    await new Promise((resolve) => setTimeout(resolve, 500))
    // Save signed-in state to 'storageState.json'.
    await page.context().storageState({ path: 'storageState.json' })

    // On the initial load you might get the Clock out of sync dialog
    if (await page.getByText('Clock out of sync').isVisible()) {
      await page.locator("text=Don't show this again").click()
      await page.locator('button:has-text("Dismiss")').click()
    }

    const adminPage = await browser.newPage()
    await adminPage.goto(`${baseURL}/tools/cmdtlmserver`)
    await new Promise((resolve) => setTimeout(resolve, 500))
    await adminPage.locator('input[name="username"]').fill('admin')
    await adminPage.locator('input[name="password"]').fill('admin')
    await adminPage.locator('input:has-text("Sign In")').click()
    await new Promise((resolve) => setTimeout(resolve, 500))
    // Save signed-in state to 'adminStorageState.json'.
    await adminPage.context().storageState({ path: 'adminStorageState.json' })
  } else {
    // Wait for the nav bar to populate
    for (let i = 0; i < 10; i++) {
      await page
        .locator('nav:has-text("CmdTlmServer")')
        .waitFor({ timeout: 30000 })
      // If we don't see CmdTlmServer then refresh the page
      if (!(await page.$('nav:has-text("CmdTlmServer")'))) {
        await page.reload()
        await new Promise((resolve) => setTimeout(resolve, 500))
      }
    }
    if (await page.getByText('Enter the password').isVisible()) {
      await page.fill('data-test=new-password', 'password')
      await page.locator('button:has-text("Login")').click()
    } else {
      await page.fill('data-test=new-password', 'password')
      await page.fill('data-test=confirm-password', 'password')
      await page.click('data-test=set-password')
    }
    await new Promise((resolve) => setTimeout(resolve, 500))

    // Save signed-in state to 'storageState.json' and adminStorageState to match Enterprise
    await page.context().storageState({ path: 'storageState.json' })
    await page.context().storageState({ path: 'adminStorageState.json' })

    // On the initial load you might get the Clock out of sync dialog
    if (await page.getByText('Clock out of sync').isVisible()) {
      await page.locator("text=Don't show this again").click()
      await page.locator('button:has-text("Dismiss")').click()
    }
  }

  await browser.close()
}

export default globalSetup
