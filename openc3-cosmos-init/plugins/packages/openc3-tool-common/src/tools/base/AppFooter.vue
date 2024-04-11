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
  <v-footer id="footer" app height="33">
    <img :src="icon" alt="OpenC3" />
    <span :class="footerClass" @click="upgrade"
      >OpenC3 {{ edition }} {{ version }} &copy; 2024 - License:
      {{ license }}</span
    >
    <v-spacer />
    <a :href="sourceUrl" class="white--text text-decoration-underline">
      Source
    </a>
    <v-spacer />
    <div class="justify-right"><clock-footer /></div>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
    ></upgrade-to-enterprise-dialog>
  </v-footer>
</template>

<script>
import ClockFooter from './components/ClockFooter.vue'
import Api from '../../services/api'
import { OpenC3Api } from '../../services/openc3-api'
import icon from '../../../public/img/icon.png'
import UpgradeToEnterpriseDialog from '../../components/UpgradeToEnterpriseDialog'

export default {
  components: {
    ClockFooter,
    UpgradeToEnterpriseDialog,
  },
  data() {
    return {
      icon: icon,
      edition: '',
      enterprise: false,
      license: '',
      sourceUrl: '',
      version: '',
      showUpgradeToEnterpriseDialog: false,
    }
  },
  created: function () {
    this.getSourceUrl()
    Api.get('/openc3-api/info').then((response) => {
      if (response.data.enterprise) {
        this.edition = 'COSMOS Enterprise'
      } else {
        this.edition = 'COSMOS Open Source'
      }
      this.enterprise = response.data.enterprise
      this.license = response.data.license
      this.version = response.data.version
    })
  },
  computed: {
    footerClass() {
      if (this.enterprise) {
        return 'enterprise'
      } else {
        return 'base'
      }
    },
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
.base {
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
