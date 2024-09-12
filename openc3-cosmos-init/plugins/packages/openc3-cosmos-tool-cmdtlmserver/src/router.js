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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createRouter, createWebHistory } from 'vue-router'

export default createRouter({
  history: createWebHistory(),
  base: process.env.BASE_URL,
  routes: [
    {
      path: '/',
      component: () => import('./tools/CmdTlmServer/CmdTlmServer.vue'),
      children: [
        {
          component: () => import('./tools/CmdTlmServer/InterfacesTab'),
          path: '',
        },
        {
          component: () => import('./tools/CmdTlmServer/InterfacesTab'),
          path: 'interfaces',
        },
        {
          component: () => import('./tools/CmdTlmServer/TargetsTab'),
          path: 'targets',
        },
        {
          component: () => import('./tools/CmdTlmServer/CmdPacketsTab'),
          path: 'cmd-packets',
        },
        {
          component: () => import('./tools/CmdTlmServer/TlmPacketsTab'),
          path: 'tlm-packets',
        },
        {
          component: () => import('./tools/CmdTlmServer/RoutersTab'),
          path: 'routers',
        },
        {
          component: () => import('./tools/CmdTlmServer/StatusTab'),
          props: { refreshInterval: 5000 },
          path: 'status',
        },
      ],
    },
    {
      path: ':pathMatch(.*)*',
      name: 'NotFound',
      component: () => import('@openc3/tool-common/src/components/NotFound'),
    },
  ],
})
