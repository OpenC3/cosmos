<!--
# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<!--
# Due to performance issues in TreeView we implement TreeNode
# based on code example provided in https://github.com/vuetifyjs/vuetify/issues/19919
-->
<template>
  <div class="tree-node">
    <div
      @click="handleClick(node)"
      class="node-content"
      v-if="!search || node.children || node.path.includes(search)"
    >
      <div class="content-wrapper">
        <v-icon
          v-if="node.children"
          class="toggle-icon"
          style="padding-right: 10px"
        >
          {{ node.isOpen ? 'mdi-menu-down' : 'mdi-menu-right' }}
        </v-icon>
        <v-icon v-if="node.children" size="small" style="padding-right: 10px">
          {{ 'mdi-folder' }}
        </v-icon>
        <v-icon
          v-else-if="node.title.includes('.rb')"
          size="small"
          style="padding-right: 10px"
        >
          {{ 'mdi-language-ruby' }}
        </v-icon>
        <v-icon
          v-else-if="node.title.includes('.py')"
          size="small"
          style="padding-right: 10px"
        >
          {{ 'mdi-language-python' }}
        </v-icon>
        <v-icon v-else size="small" style="padding-right: 10px">
          {{ 'mdi-file-document' }}
        </v-icon>
        <span
          class="title"
          :tabindex="node.children ? -1 : 0"
          @keyup.enter="handleClick(node)"
        >
          {{ node.title }}
        </span>

        <v-btn
          v-if="node.title === '__TEMP__'"
          icon
          @click="emit('delete')"
          style="margin-left: auto"
        >
          <v-icon> mdi-delete </v-icon>
        </v-btn>
      </div>
    </div>
    <div v-else></div>
    <div v-if="node.children && node.isOpen" class="children">
      <tree-node
        v-for="child in node.children"
        :key="child.id"
        :node="child"
        :search="search"
        @node-toggled="bubbleNodeToggled"
        @request="bubbleNodeRequest"
      ></tree-node>
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
  search: {
    type: String,
    default: '',
  },
})

const isOpen = ref(props.node.isOpen || false)

watch(
  () => props.node.isOpen,
  (newpath) => {
    isOpen.path = newpath
  },
)

watch(
  () => props.search,
  (newSearch) => {
    if (newSearch) {
      if (!props.node.isOpen) toggle()
    } else {
      if (props.node.isOpen) toggle()
    }
  },
)

const emit = defineEmits(['nodeToggled', 'request'])

const handleClick = (node) => {
  if (node.children) toggle()
  else request(node)
}
const toggle = () => {
  if (props.node.children) {
    isOpen.path = !isOpen.path
    props.node.isOpen = isOpen.path
    emit('nodeToggled', props.node.id, isOpen.path)
  }
}
const request = (node) => {
  emit('request', node)
}

// Bubble up the event for the nested tree-nodes
const bubbleNodeToggled = (nodeName, isOpen) => {
  emit('nodeToggled', nodeName, isOpen)
}
const bubbleNodeRequest = (node) => {
  emit('request', node)
}
</script>

<style scoped>
.children {
  padding-left: 25px;
}
.content-wrapper {
  align-items: center;
  display: flex;
  max-height: 38px;
}
.node-content {
  cursor: pointer;
  overflow: hidden;
  user-select: none;
  white-space: nowrap;
}
.node-content:hover {
  background-color: rgba(211, 211, 211, 0.2);
  transition: background-color 0.3s ease;
}
.title {
  overflow: hidden;
  text-overflow: ellipsis;
}
.toggle-icon {
  width: 20px;
}
.tree-node {
  line-height: 1.8;
  position: relative;
}
</style>
