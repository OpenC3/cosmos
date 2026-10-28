<template>
  <div
    class="d-flex flex-column flex-grow-1 align-center justify-center ga-1 pa-2"
    :class="{ 'cursor-pointer': !!openDetails }"
    @click="showDetails()"
  >
    <div class="d-flex align-center ga-2">
      <StatusSymbol :level="first.level" :size="16" />
      <span class="text-medium-emphasis text-caption">{{ first.label }}</span>
    </div>
    <div :class="['value', { 'text-disabled': first.stale }]">
      {{ text }}
      <span class="text-body-2 text-medium-emphasis">{{ first.units }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { sdk } from './panelSdk'

// Every panel gets its PANEL ... END block as `panel`
const props = defineProps({
  panel: { type: Object, required: true },
})

// Polls the panel's ITEMs and reports its status to the dashboard.
// itemStates has one entry per item: label, text, number, units, level,
// stale and limits; first is the first one. See the custom panels guide.
const { first, showDetails, openDetails } = sdk.useTlmPanel(props)
const { StatusSymbol } = sdk.components

const text = computed(() => {
  const decimals = sdk.option(props.panel, 'DECIMALS')
  if (decimals === null || first.value.number === null) return first.value.text
  return first.value.number.toFixed(decimals)
})
</script>

<style scoped>
.value {
  font-size: 32px;
  font-weight: 500;
}
</style>
