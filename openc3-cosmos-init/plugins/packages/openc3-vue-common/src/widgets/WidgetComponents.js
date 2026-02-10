/*
# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { defineAsyncComponent } from 'vue'
import upperFirst from 'lodash/upperFirst'
import camelCase from 'lodash/camelCase'

const componentImports = import.meta.glob('./*Widget.vue')
const components = Object.entries(componentImports).reduce(
  (acc, [filename, importFunction]) => {
    filename = filename.split('/').pop() // trims off the leading './'
    // Get PascalCase name of component
    const componentName = upperFirst(
      camelCase(
        filename.replace(/\.\w+$/, ''), // trims off the trailing '.vue'
      ),
    )
    // Register component locally
    return {
      ...acc,
      [componentName]: defineAsyncComponent(importFunction),
    }
  },
  {},
)

export default {
  components,
}
