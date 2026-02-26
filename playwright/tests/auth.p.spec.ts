/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
*/

import { test, expect } from '@playwright/test'

test.describe('Auth API', () => {
  test('verifies rate limiting is enforced', async ({ request }) => {
    if (process.env.ENTERPRISE === '1') {
      // Rate limiting handled by Keycloak in Enterprise
      return
    }

    const maxRequests = parseInt(process.env.OPENC3_AUTH_RATE_LIMIT_TO || '10')

    let gotRateLimited = false
    for (let i = 0; i <= maxRequests; i++) {
      const response = await request.post('/openc3-api/auth/verify', {
        data: { password: 'whatever' }
      })

      if (response.status() === 429) {
        gotRateLimited = true
        break
      }
    }

    expect(gotRateLimited).toBe(true)
  })
})
