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
  <div>
    <div class="text-subtitle-2 mb-1">Targets</div>
    <div class="text-caption text-medium-emphasis mb-3">
      Show out of limits items for these targets. Leave empty for all targets.
    </div>
    <v-autocomplete
      :model-value="panel.targets"
      :items="targetNames"
      label="Targets"
      placeholder="All targets"
      multiple
      chips
      closable-chips
      density="compact"
      variant="outlined"
      hide-details
      data-test="config-targets"
      @update:model-value="(targets) => $emit('update', { targets })"
    />
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { targetNames as loadTargetNames } from '../../composables/targets'

defineProps({
  panel: { type: Object, required: true },
})
defineEmits(['update'])

const targetNames = ref([])
loadTargetNames().then((names) => {
  targetNames.value = names
})
</script>
