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
  <!-- The thin centered title bar COSMOS dialogs use -->
  <v-toolbar height="24">
    <v-spacer />
    <span>{{ title }}</span>
    <v-spacer />
    <v-btn
      icon="mdi-close-box"
      variant="text"
      density="compact"
      aria-label="Close"
      @click="$emit('close')"
    />
  </v-toolbar>
</template>

<script setup>
defineProps({
  title: { type: String, required: true },
})
defineEmits(['close'])
</script>
