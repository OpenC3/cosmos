/*
# Copyright 2024 OpenC3, Inc.
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

import { defineAsyncComponent } from 'vue'
import upperFirst from 'lodash/upperFirst'
import camelCase from 'lodash/camelCase'

// Globally register all XxxWidget.vue components
const requireComponent = require.context(
  // The relative path of the components folder
  '@openc3/tool-common/src/components/widgets',
  // Whether or not to look in subfolders
  false,
  // The regular expression used to match base component filenames
  /[A-Z][a-z]+Widget\.vue$/,
)
const components = {}
requireComponent.keys().map((filename) => {
  filename = filename.split('/').pop() // trims off the leading './'
  // Get PascalCase name of component
  const componentName = upperFirst(
    camelCase(
      filename.replace(/\.\w+$/, ''), // trims off the trailing '.vue'
    ),
  )
  // Register component locally
  components[componentName] = defineAsyncComponent(
    () => import(`@openc3/tool-common/src/components/widgets/${filename}`),
  )
})

export default {
  components,
}
