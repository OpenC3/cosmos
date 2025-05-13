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
