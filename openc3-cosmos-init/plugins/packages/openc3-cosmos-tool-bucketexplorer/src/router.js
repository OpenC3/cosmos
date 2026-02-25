/*
# Copyright 2023 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createRouter, createWebHistory } from 'vue-router'
import { prependBasePath } from '@openc3/js-common/utils'

const routes = [
  {
    path: '/:path*',
    name: 'Bucket Explorer',
    component: () => import('./tools/BucketExplorer/BucketExplorer.vue'),
  },
  // No NotFound component because we're matching everything with :path*
]
routes.forEach(prependBasePath)

export default createRouter({
  history: createWebHistory(),
  routes,
})
