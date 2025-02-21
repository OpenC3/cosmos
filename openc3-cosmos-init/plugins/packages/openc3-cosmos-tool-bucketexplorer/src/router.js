/*
# Copyright 2023 OpenC3, Inc.
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
