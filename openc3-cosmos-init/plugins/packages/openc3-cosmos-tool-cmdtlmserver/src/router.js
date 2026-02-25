/*
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createRouter, createWebHistory } from 'vue-router'
import { prependBasePath } from '@openc3/js-common/utils'
import { NotFound } from '@openc3/vue-common/components'

const routes = [
  {
    path: '',
    component: () => import('./tools/CmdTlmServer/CmdTlmServer.vue'),
    children: [
      {
        component: () => import('./tools/CmdTlmServer/InterfacesTab'),
        path: '',
      },
      {
        component: () => import('./tools/CmdTlmServer/InterfacesTab'),
        name: 'InterfacesTab',
        path: 'interfaces',
      },
      {
        component: () => import('./tools/CmdTlmServer/TargetsTab'),
        name: 'TargetsTab',
        path: 'targets',
      },
      {
        component: () => import('./tools/CmdTlmServer/CmdPacketsTab'),
        name: 'CmdPacketsTab',
        path: 'cmd-packets',
      },
      {
        component: () => import('./tools/CmdTlmServer/TlmPacketsTab'),
        name: 'TlmPacketsTab',
        path: 'tlm-packets',
      },
      {
        component: () => import('./tools/CmdTlmServer/RoutersTab'),
        name: 'RoutersTab',
        path: 'routers',
      },
      {
        component: () => import('./tools/CmdTlmServer/DataFlowsTab'),
        name: 'DataFlowsTab',
        path: 'data-flows',
      },
      {
        component: () => import('./tools/CmdTlmServer/StatusTab'),
        name: 'StatusTab',
        props: { refreshInterval: 5000 },
        path: 'status',
      },
    ],
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'NotFound',
    component: NotFound,
  },
]

routes.forEach(prependBasePath)

export default createRouter({
  history: createWebHistory(),
  routes,
})
