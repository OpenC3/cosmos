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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-footer v-if="!chromeless" id="footer" app height="33">
    <img :src="icon" alt="OpenC3" />
    <span :class="footerClass" @click="upgrade">
      OpenC3 {{ edition }} {{ version }} &copy; 2025 - License:
      {{ license }}
    </span>
    <v-spacer />
    <a :href="sourceUrl" class="text-white text-decoration-underline">
      Source
    </a>
    <v-spacer />
    <div class="justify-right"><clock-footer /></div>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Enterprise is Commercially Licensed"
    />
  </v-footer>
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { UpgradeToEnterpriseDialog } from '@/components'
import ClockFooter from './ClockFooter.vue'

export default {
  components: {
    ClockFooter,
    UpgradeToEnterpriseDialog,
  },
  data() {
    return {
      icon: '/img/icon.png',
      edition: '',
      enterprise: false,
      license: '',
      sourceUrl: '',
      version: '',
      showUpgradeToEnterpriseDialog: false,
      chromeless: null,
    }
  },
  computed: {
    footerClass() {
      if (this.enterprise) {
        return 'enterprise'
      } else {
        return 'core'
      }
    },
  },
  created: function () {
    const urlParams = new URLSearchParams(window.location.search)
    this.chromeless = urlParams.get('chromeless')

    this.getSourceUrl()
    Api.get('/openc3-api/info').then((response) => {
      if (response.data.enterprise) {
        this.edition = 'COSMOS Enterprise'
      } else {
        this.edition = 'COSMOS Core'
      }
      this.enterprise = response.data.enterprise
      this.license = response.data.license
      this.version = response.data.version
    })
  },
  methods: {
    getSourceUrl: function () {
      new OpenC3Api().get_settings(['source_url']).then((response) => {
        this.sourceUrl = response[0]
      })
    },
    upgrade: function () {
      if (!this.enterprise) {
        this.showUpgradeToEnterpriseDialog = true
      }
    },
  },
}
</script>

<style scoped>
.core {
  margin-left: 5px;
  cursor: pointer;
}
.enterprise {
  margin-left: 5px;
}
#footer {
  z-index: 1000; /* On TOP! */
  background-color: var(--gsb-color-background) !important;
}
</style>

<style>
/* Classification banners */
#footer {
  margin-bottom: var(--classification-height-bottom);
}
/* END classification banners */
</style>
