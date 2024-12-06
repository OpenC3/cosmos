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

const DEFAULT_TOOL_PATH = '/tools/cmdtlmserver'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/login',
      name: 'Login',
      component: () =>
        import('@openc3/tool-common/src/tools/base/components/Login'),
    },
    {
      // Empty component for all other routes to avoid VueRouter warnings, since all other routes are handled by single-spa
      path: '/:pathMatch(.*)*',
      name: '',
      component: () => import('@openc3/tool-common/src/components/Empty'),
    },
  ],
})

router.beforeEach(({ path }) => {
  if (['/', '/tools', '/tools/'].includes(path)) {
    singleSpaNavigate(DEFAULT_TOOL_PATH)
  }
})

export default router
