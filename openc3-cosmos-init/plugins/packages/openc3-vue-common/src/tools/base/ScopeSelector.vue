<!--
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
-->

<template>
  <div style="cursor: pointer" @click="showUpgradeToEnterpriseDialog = true">
    <v-select
      v-model="scope"
      :items="scopes"
      :disabled="scopes.length <= 1"
      label="Scope"
      density="compact"
      variant="outlined"
      hide-details
      style="max-width: 150px"
    />
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Enterprise allows additional Scopes"
    />
  </div>
</template>

<script>
import { UpgradeToEnterpriseDialog } from '@/components'

export default {
  components: {
    UpgradeToEnterpriseDialog,
  },
  data: function () {
    return {
      // COSMOS Core only has one scope: 'DEFAULT'
      scopes: ['DEFAULT'],
      scope: 'DEFAULT',
      showUpgradeToEnterpriseDialog: false,
    }
  },
}
</script>
