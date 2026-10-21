<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-select
    v-if="param.states"
    :model-value="modelValue"
    :items="Object.keys(param.states)"
    density="compact"
    variant="outlined"
    hide-details
    :data-test="`command-param-${param.name}`"
    @update:model-value="(value) => $emit('update:modelValue', value)"
  />
  <v-text-field
    v-else
    :model-value="modelValue"
    class="num"
    density="compact"
    variant="outlined"
    hide-details
    :suffix="param.units"
    :placeholder="param.required ? 'Required' : ''"
    :data-test="`command-param-${param.name}`"
    @update:model-value="(value) => $emit('update:modelValue', value)"
  />
</template>

<script>
// One COMMAND panel parameter: a select for states, a text field otherwise.
// The panel shows the name beside it.
export default {
  props: {
    param: { type: Object, required: true },
    modelValue: { type: [String, Number], default: '' },
  },
  emits: ['update:modelValue'],
}
</script>
