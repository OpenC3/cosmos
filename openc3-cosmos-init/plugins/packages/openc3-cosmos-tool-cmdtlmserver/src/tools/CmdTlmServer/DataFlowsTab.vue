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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <InterfaceFlowChart
    :interface-details="interfaceDetails"
    :router-details="routerDetails"
    style="height: 80vh"
  />
</template>

<script>
import Updater from './Updater'
import InterfaceFlowChart from './InterfaceComponents/InterfaceFlowChart.vue'
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  components: {
    InterfaceFlowChart,
  },
  mixins: [Updater],
  data() {
    return {
      api: null,
      interfaceDetails: null,
      routerDetails: null,
    }
  },
  created() {
    this.refreshInterval = 10000 // 10 s
    this.api = new OpenC3Api()
    this.update()
  },
  methods: {
    update() {
      this.api.get_interface_names().then((names) => {
        const promises = [...names].map((name) => {
          return this.api.interface_details(name)
        })

        Promise.all(promises).then((responses) => {
          this.interfaceDetails = {}
          let index = 0
          names.forEach((name) => {
            this.interfaceDetails[name] = responses[index]
            index += 1
          })
        })
      })

      this.api.get_router_names().then((names) => {
        const promises = [...names].map((name) => {
          return this.api.router_details(name)
        })

        Promise.all(promises).then((responses) => {
          this.routerDetails = {}
          let index = 0
          names.forEach((name) => {
            this.routerDetails[name] = responses[index]
            index += 1
          })
        })
      })
    },
  },
}
</script>
