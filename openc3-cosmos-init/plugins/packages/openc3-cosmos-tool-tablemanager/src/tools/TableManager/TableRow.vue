<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <tr>
    <td class="text-start">{{ dataItems[0].index }}</td>
    <td v-if="oneDimensional" class="text-start">{{ dataItems[0].name }}</td>
    <table-item
      v-for="(item, index) in dataItems"
      :key="item.name"
      :item="item"
      @change.self="onChange(item, index, $event)"
    />
  </tr>
</template>

<script>
import TableItem from '@/tools/TableManager/TableItem'

export default {
  components: {
    TableItem,
  },
  props: {
    items: {
      type: Object,
      required: true,
    },
  },
  emits: ['change'],
  data() {
    return {
      dataItems: this.items,
    }
  },
  computed: {
    oneDimensional() {
      if (this.dataItems.length === 1) {
        return true
      } else {
        return false
      }
    },
  },
  methods: {
    onChange: function (item, index, event) {
      this.$emit('change', { index, event })
    },
  },
}
</script>
