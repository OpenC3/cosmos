/*
# Copyright 2024 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { createVuetify } from 'vuetify'
import { mdi } from 'vuetify/iconsets/mdi'
import { AstroIconVuetifySets, CustomIconSet } from '@/icons'
import cosmosDark from './cosmosThemeDark'

export default createVuetify({
  theme: {
    defaultTheme: 'cosmosDark',
    themes: {
      cosmosDark,
    },
  },
  icons: {
    defaultSet: 'mdi',
    sets: {
      mdi,
      ...AstroIconVuetifySets,
      ...CustomIconSet,
    },
  },
})
