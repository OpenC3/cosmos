/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createRouter, createWebHistory } from 'vue-router'
import { NotFound } from '@openc3/vue-common/components'
import { Login } from '@openc3/vue-common/tools/base'
import { Api } from '@openc3/js-common/services'

const ROOT_PATHS = ['/', '/tools', '/tools/'] // where to redirect from
const DEFAULT_TOOL_TIMEOUT_MS = 150 // how long to wait to get the tool to redirect to (ms)
const DEFAULT_TOOL_URL = '/tools/cmdtlmserver' // where to redirect to if we can't figure it out in time

const getFirstTool = async () => {
  // Tools are global and are always installed into the DEFAULT scope

  // Skip API call if not authenticated to avoid redirect loop
  if (!localStorage.openc3Token) {
    return { url: DEFAULT_TOOL_URL }
  }
  const { data } = await Api.get('/openc3-api/tools/all', {
    params: { scope: 'DEFAULT' },
  })
  const [_, firstTool] = Object.entries(data).find(([name, tool]) => {
    return name !== 'Admin' && tool.shown
  })
  return firstTool
}

const timeout = (ms) => {
  return new Promise((res) => {
    setTimeout(res, ms)
  })
}

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: Login,
    },
    {
      path: '/:pathMatch(.*)*',
      name: '',
      component: NotFound,
    },
  ],
})

router.beforeEach(async (to) => {
  if (ROOT_PATHS.includes(to.fullPath)) {
    const firstTool = await Promise.race([
      getFirstTool(),
      timeout(DEFAULT_TOOL_TIMEOUT_MS),
    ])
    return firstTool?.url || DEFAULT_TOOL_URL
  }
})

export default router
