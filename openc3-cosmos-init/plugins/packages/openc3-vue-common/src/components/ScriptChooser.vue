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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-row>
      <v-autocomplete
        v-model="selected"
        v-model:search="search"
        density="compact"
        variant="outlined"
        hide-no-data
        hide-details
        class="mb-5"
        label="Select script"
        :loading="loading"
        :items="items"
        data-test="select-script"
      />
    </v-row>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  // TODO: cache items
  // this was previously handled by Vuetify and the `cache-items` prop on `v-autocomplete`, but that feature was
  // dropped in Vuetify 3
  props: {
    modelValue: String, // modelValue is the default prop when using v-model
  },
  data() {
    return {
      loading: false,
      search: '',
      selected: this.modelValue,
      scripts: [],
      items: [],
    }
  },
  watch: {
    selected(newVal, oldVal) {
      if (newVal !== oldVal) {
        if (newVal.slice(-1) === '*') {
          // Remove the * before returning
          this.$emit('file', newVal.substring(0, newVal.length - 1))
        } else {
          this.$emit('file', newVal)
        }
      }
    },
    search(val) {
      val && val !== this.selected && this.querySelections(val)
    },
  },
  created() {
    this.loading = true
    Api.get('/script-api/scripts')
      .then((response) => {
        this.scripts = response.data.filter((filename) => {
          return filename.includes('.rb') || filename.includes('.py')
        })
        this.items = this.scripts
      })
      .catch((error) => {
        this.$emit('error', {
          type: 'error',
          text: `Failed to connect to OpenC3. ${error}`,
          error: error,
        })
      })
    this.selected = this.modelValue ? this.modelValue : null
    this.loading = false
  },
  methods: {
    querySelections: function (v) {
      this.loading = true
      // Simulated ajax query
      setTimeout(() => {
        this.items = this.scripts.filter((e) => {
          return (e || '').toLowerCase().indexOf((v || '').toLowerCase()) > -1
        })
        this.loading = false
      }, 500)
    },
  },
}
</script>
