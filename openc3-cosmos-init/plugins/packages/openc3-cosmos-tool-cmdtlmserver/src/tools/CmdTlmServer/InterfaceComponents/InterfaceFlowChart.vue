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

<script setup>
import { ref, watch, defineProps, inject, nextTick } from 'vue'
import { VueFlow, Handle, useVueFlow } from '@vue-flow/core'
import { ControlButton, Controls } from '@vue-flow/controls'
import { Background } from '@vue-flow/background'
import DetailsTable from './DetailsTable.vue'
import InterfaceNode from './InterfaceNode.vue'
import RouterNode from './RouterNode.vue'
import CosmosNode from './CosmosNode.vue'
import TargetNode from './TargetNode.vue'
import WriteProtocolNode from './WriteProtocolNode.vue'
import ReadProtocolNode from './ReadProtocolNode.vue'
import { OpenC3Api } from '@openc3/js-common/services'
import { useLayout } from './useLayout'
const { layout } = useLayout()

const {
  onConnect,
  addEdges,
  onNodesChange,
  applyNodeChanges,
  onEdgesChange,
  applyEdgeChanges,
  fitView,
} = useVueFlow()

const dialog = inject('dialog')
const api = new OpenC3Api()

const props = defineProps(['interfaceDetails', 'routerDetails'])
const nodes = ref([])
const edges = ref([])

let layoutNeeded = false

async function layoutGraph(direction, force = false) {
  if (layoutNeeded || force) {
    nodes.value = layout(nodes.value, edges.value, direction)
    layoutNeeded = false
    nextTick(() => {
      fitView()
    })
  }
}

onConnect((params) => {
  // params = { source: 'interface__EXAMPLE_INT',
  // sourceHandle: 'interface__cmd__input',
  // target: 'cosmos__EXAMPLE',
  // targetHandle: 'cosmos__cmd' }

  let interface_source = params.source.startsWith('interface__')
  let interface_target = params.target.startsWith('interface__')
  let router_source = params.source.startsWith('router__')
  let router_target = params.target.startsWith('router__')
  let cosmos_source = params.source.startsWith('cosmos__')
  let cosmos_target = params.target.startsWith('cosmos__')
  let target_source = params.source.startsWith('target__')
  let target_target = params.target.startsWith('target__')
  let source_cmd_or_tlm = params.sourceHandle.split('__')[1]
  let target_cmd_or_tlm = params.targetHandle.split('__')[1]

  // cmd_or_tlm must match
  if (source_cmd_or_tlm !== target_cmd_or_tlm) {
    return
  }
  // Interface can't connect to itself
  if (interface_source && interface_target) {
    return
  }
  // Router can't connect to itself
  if (router_source && router_target) {
    return
  }
  // Router can't connect to interface
  if (router_source && interface_target) {
    return
  }
  if (interface_source && router_target) {
    return
  }
  // Cosmos can't connect to itself
  if (cosmos_source && cosmos_target) {
    return
  }
  // Target can't connect to itself
  if (target_source && target_target) {
    return
  }
  // Cosmos can't connect directly to target
  if (cosmos_source && target_target) {
    return
  }
  if (target_source && cosmos_target) {
    return
  }

  // Build id
  let id = ''
  if (cosmos_source) {
    id = id + `cosmos__${params.source.split('__')[1]}`
  }
  if (cosmos_target) {
    id = id + `cosmos__${params.target.split('__')[1]}`
  }
  if (id.length == 0) {
    // Interface or Router source
    if (interface_source) {
      id = id + `interface__${params.source.split('__')[1]}`
    }
    if (interface_target) {
      id = id + `interface__${params.target.split('__')[1]}`
    }
    if (router_source) {
      id = id + `router__${params.source.split('__')[1]}`
    }
    if (router_target) {
      id = id + `router__${params.target.split('__')[1]}`
    }
  }
  if (id.startsWith('cosmos__')) {
    // Interface or Router target
    if (interface_source) {
      id = id + `__interface__${params.source.split('__')[1]}`
    }
    if (interface_target) {
      id = id + `__interface__${params.target.split('__')[1]}`
    }
    if (router_source) {
      id = id + `__router__${params.source.split('__')[1]}`
    }
    if (router_target) {
      id = id + `__router__${params.target.split('__')[1]}`
    }
  }
  // Target is always at the end
  if (target_source) {
    id = id + `__target__${params.source.split('__')[1]}`
  }
  if (target_target) {
    id = id + `__target__${params.target.split('__')[1]}`
  }
  id = id + `__${source_cmd_or_tlm}`

  params.id = id

  // Prevent dup edges
  let found = false
  edges.value.forEach((edge) => {
    if (edge.id === id) {
      found = true
      return
    }
  })
  if (found) {
    return
  }

  let interface_or_router = ''
  let target_name = ''
  let interface_or_router_name = ''
  let split_id = id.split('__')
  let first_type = split_id[0]
  let cmd_or_tlm = split_id[4]
  if (first_type === 'cosmos') {
    // Enable Target
    target_name = split_id[1]
    interface_or_router = split_id[2]
    interface_or_router_name = split_id[3]

    if (cmd_or_tlm == 'cmd') {
      params.type = 'default'
      params.label = 'CMD Enable'
      params.markerStart = { type: 'arrowclosed' }
    } else {
      params.type = 'default'
      params.label = 'Tlm Enable'
      params.markerEnd = { type: 'arrowclosed' }
    }

    if (interface_or_router === 'interface') {
      api
        .interface_target_enable(
          interface_or_router_name,
          target_name,
          cmd_or_tlm === 'cmd',
          cmd_or_tlm === 'tlm',
        )
        .then((response) => {
          addEdges(params)
          edges.value.push(params)
        })
    } else {
      api
        .router_target_enable(
          interface_or_router_name,
          target_name,
          cmd_or_tlm === 'cmd',
          cmd_or_tlm === 'tlm',
        )
        .then((response) => {
          addEdges(params)
          edges.value.push(params)
        })
    }
  } else {
    // Map Target
    interface_or_router = split_id[0]
    interface_or_router_name = split_id[1]
    target_name = split_id[3]

    if (cmd_or_tlm == 'cmd') {
      params.type = 'default'
      params.label = 'CMD Map'
      params.markerStart = { type: 'arrowclosed' }
    } else {
      params.type = 'default'
      params.label = 'Tlm Map'
      params.markerEnd = { type: 'arrowclosed' }
    }

    if (interface_or_router === 'interface') {
      dialog
        .confirm(
          `${params.label} target ${target_name} to interface ${interface_or_router_name}? Note this will cause the interface to restart.`,
          {
            okText: 'Map',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          api
            .map_target_to_interface(
              target_name,
              interface_or_router_name,
              cmd_or_tlm === 'cmd',
              cmd_or_tlm === 'tlm',
              false,
            )
            .then((response) => {
              addEdges(params)
              edges.value.push(params)
            })
        })
    } else {
      dialog
        .confirm(
          `${params.label} target ${target_name} to router ${interface_or_router_name}? Note this will cause the router to restart.`,
          {
            okText: 'Map',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          api
            .map_target_to_router(
              target_name,
              interface_or_router_name,
              cmd_or_tlm === 'cmd',
              cmd_or_tlm === 'tlm',
              false,
            )
            .then((response) => {
              addEdges(params)
              edges.value.push(params)
            })
        })
    }
  }
})

onNodesChange(async (changes) => {
  const nextChanges = []

  for (const change of changes) {
    if (change.type !== 'remove') {
      // Allow changes except remove
      nextChanges.push(change)
    }
    if (change.type === 'dimensions') {
      layoutNeeded = true
      nextTick(() => {
        layoutGraph('LR')
      })
    }
  }

  applyNodeChanges(nextChanges)
})

onEdgesChange(async (changes) => {
  const nextChanges = []
  for (const change of changes) {
    if (change.type !== 'remove') {
      // Allow changes except remove
      nextChanges.push(change)
    } else {
      let dialog_text = ''
      let dialog_ok = ''
      let target_name = ''
      let interface_or_router = ''
      let interface_or_router_name = ''
      let split_id = change.id.split('__')
      let first_type = split_id[0]
      let cmd_or_tlm = split_id[4]
      if (first_type === 'cosmos') {
        target_name = split_id[1]
        interface_or_router = split_id[2]
        interface_or_router_name = split_id[3]
        dialog_text = `Disable ${target_name} ${cmd_or_tlm} with ${interface_or_router} ${interface_or_router_name}?`
        dialog_ok = 'Disable'
      } else {
        interface_or_router = split_id[0]
        interface_or_router_name = split_id[1]
        target_name = split_id[3]
        dialog_text = `Unmap ${target_name} ${cmd_or_tlm} with ${interface_or_router} ${interface_or_router_name}? Note this will cause the ${interface_or_router} to restart.`
        dialog_ok = 'Unmap'
      }
      // Implement side effects of deleting edges
      dialog
        .confirm(dialog_text, {
          okText: dialog_ok,
          cancelText: 'Cancel',
        })
        .then(() => {
          if (first_type == 'cosmos') {
            if (interface_or_router == 'interface') {
              api
                .interface_target_disable(
                  interface_or_router_name,
                  target_name,
                  cmd_or_tlm === 'cmd',
                  cmd_or_tlm === 'tlm',
                )
                .then((response) => {
                  applyEdgeChanges([change])
                  edges.value.forEach((edge, index) => {
                    if (edge.id === change.id) {
                      edges.value.splice(index, 1)
                      return
                    }
                  })
                })
            } else {
              api
                .router_target_disable(
                  interface_or_router_name,
                  target_name,
                  cmd_or_tlm === 'cmd',
                  cmd_or_tlm === 'tlm',
                )
                .then((response) => {
                  applyEdgeChanges([change])
                  edges.value.forEach((edge, index) => {
                    if (edge.id === change.id) {
                      edges.value.splice(index, 1)
                      return
                    }
                  })
                })
            }
          } else {
            if (interface_or_router == 'interface') {
              api
                .unmap_target_from_interface(
                  target_name,
                  interface_or_router_name,
                  cmd_or_tlm === 'cmd',
                  cmd_or_tlm === 'tlm',
                )
                .then((response) => {
                  applyEdgeChanges([change])
                  edges.value.forEach((edge, index) => {
                    if (edge.id === change.id) {
                      edges.value.splice(index, 1)
                      return
                    }
                  })
                })
            } else {
              api
                .unmap_target_from_router(
                  target_name,
                  interface_or_router_name,
                  cmd_or_tlm === 'cmd',
                  cmd_or_tlm === 'tlm',
                )
                .then((response) => {
                  applyEdgeChanges([change])
                  edges.value.forEach((edge, index) => {
                    if (edge.id === change.id) {
                      edges.value.splice(index, 1)
                      return
                    }
                  })
                })
            }
          }
        })
    }
  }

  applyEdgeChanges(nextChanges)
})

const detailsDialog = ref(false)
const selectedMode = ref(null)
const selectedDetails = ref(null)
const selectedWriteProtocolIndex = ref(null)
const selectedReadProtocolIndex = ref(null)

function onNodeClick(event) {
  if (event.node.type === 'interface') {
    selectedMode.value = 'Interface'
    selectedDetails.value = props.interfaceDetails[event.node.data.label]
    selectedWriteProtocolIndex.value = null
    selectedReadProtocolIndex.value = null
    detailsDialog.value = true
  } else if (event.node.type == 'router') {
    selectedMode.value = 'Router'
    selectedDetails.value = props.routerDetails[event.node.data.label]
    selectedWriteProtocolIndex.value = null
    selectedReadProtocolIndex.value = null
    detailsDialog.value = true
  } else if (
    event.node.type === 'read-protocol' ||
    event.node.type == 'write-protocol'
  ) {
    if (event.node.data.interface) {
      selectedMode.value = 'Interface'
      selectedDetails.value = props.interfaceDetails[event.node.data.interface]
    } else {
      selectedMode.value = 'Router'
      selectedDetails.value = props.routerDetails[event.node.data.router]
    }
    selectedWriteProtocolIndex.value = null
    selectedReadProtocolIndex.value = event.node.data.index
    detailsDialog.value = true
  }
}

function updateFlowChart() {
  nodes.value = []
  edges.value = []
  const targetNames = []

  let interfaceDetails = props.interfaceDetails || {}
  for (const interfaceName in interfaceDetails) {
    // Add Edges for CMD Map
    let cmdTargetNames =
      props.interfaceDetails[interfaceName].cmd_target_names || []
    cmdTargetNames.forEach((cmdTargetName) => {
      if (!targetNames.includes(cmdTargetName)) {
        targetNames.push(cmdTargetName)
      }

      // Create edge for this cmdTargetName from Interface Node to Target Node
      const interfaceCmdToTargetCmd = {
        id: `interface__${interfaceName}__target__${cmdTargetName}__cmd`,
        source: `interface__${interfaceName}`,
        target: `target__${cmdTargetName}`,
        sourceHandle: 'interface__cmd__output',
        targetHandle: 'target__cmd',
        type: 'default',
        label: 'CMD Map',
        markerEnd: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(interfaceCmdToTargetCmd)
    })

    // Add Edges for CMD Enable
    for (const [cmdTargetName, enabled] of Object.entries(
      props.interfaceDetails[interfaceName].cmd_target_enabled,
    )) {
      if (cmdTargetName === 'UNKNOWN') {
        continue
      }
      if (!enabled) {
        continue
      }
      const cosmosCmdToInterfaceCmd = {
        id: `cosmos__${cmdTargetName}__interface__${interfaceName}__cmd`,
        target: `interface__${interfaceName}`,
        source: `cosmos__${cmdTargetName}`,
        sourceHandle: 'cosmos__cmd',
        targetHandle: 'interface__cmd__input',
        type: 'default',
        label: 'CMD Enable',
        markerEnd: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(cosmosCmdToInterfaceCmd)
    }

    // Add Edges for TLM Map
    let tlmTargetNames =
      props.interfaceDetails[interfaceName].tlm_target_names || []
    tlmTargetNames.forEach((tlmTargetName) => {
      if (!targetNames.includes(tlmTargetName)) {
        targetNames.push(tlmTargetName)
      }

      // Create edge for this tlmTargetName from Interface Node to Target Node
      const interfaceTlmToTargetTlm = {
        id: `interface__${interfaceName}__target__${tlmTargetName}__tlm`,
        source: `interface__${interfaceName}`,
        target: `target__${tlmTargetName}`,
        sourceHandle: 'interface__tlm__output',
        targetHandle: 'target__tlm',
        type: 'default',
        label: 'TLM Map',
        markerStart: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(interfaceTlmToTargetTlm)
    })

    // Add Edges for TLM Enable
    for (const [tlmTargetName, enabled] of Object.entries(
      props.interfaceDetails[interfaceName].tlm_target_enabled,
    )) {
      if (tlmTargetName === 'UNKNOWN') {
        continue
      }
      if (!enabled) {
        continue
      }
      const cosmosTlmToInterfaceTlm = {
        id: `cosmos__${tlmTargetName}__interface__${interfaceName}__tlm`,
        target: `interface__${interfaceName}`,
        source: `cosmos__${tlmTargetName}`,
        sourceHandle: 'cosmos__tlm',
        targetHandle: 'interface__tlm__input',
        type: 'default',
        label: 'TLM Enable',
        markerStart: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(cosmosTlmToInterfaceTlm)
    }
  }

  let routerDetails = props.routerDetails || {}
  for (const routerName in routerDetails) {
    // Add Edges for CMD Map
    let cmdTargetNames = props.routerDetails[routerName].cmd_target_names || []
    cmdTargetNames.forEach((cmdTargetName) => {
      if (!targetNames.includes(cmdTargetName)) {
        targetNames.push(cmdTargetName)
      }

      // Create edge for this cmdTargetName from Router Node to Target Node
      const routerCmdToTargetCmd = {
        id: `router__${routerName}__target__${cmdTargetName}__cmd`,
        source: `router__${routerName}`,
        target: `target__${cmdTargetName}`,
        sourceHandle: 'router__cmd__output',
        targetHandle: 'target__cmd',
        type: 'default',
        label: 'CMD Map',
        markerEnd: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(routerCmdToTargetCmd)
    })

    // Add Edges for CMD Enable
    for (const [cmdTargetName, enabled] of Object.entries(
      props.routerDetails[routerName].cmd_target_enabled,
    )) {
      if (cmdTargetName === 'UNKNOWN') {
        continue
      }
      if (!enabled) {
        continue
      }
      const cosmosCmdToRouterCmd = {
        id: `cosmos__${cmdTargetName}__router__${routerName}__cmd`,
        target: `router__${routerName}`,
        source: `cosmos__${cmdTargetName}`,
        sourceHandle: 'cosmos__cmd',
        targetHandle: 'router__cmd__input',
        type: 'default',
        label: 'CMD Enable',
        markerEnd: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(cosmosCmdToRouterCmd)
    }

    // Add Edges for TLM Map
    let tlmTargetNames = props.routerDetails[routerName].tlm_target_names || []
    tlmTargetNames.forEach((tlmTargetName) => {
      if (!targetNames.includes(tlmTargetName)) {
        targetNames.push(tlmTargetName)
      }

      // Create edge for this tlmTargetName from Router Node to Target Node
      const routerTlmToTargetTlm = {
        id: `router__${routerName}__target__${tlmTargetName}__tlm`,
        source: `router__${routerName}`,
        target: `target__${tlmTargetName}`,
        sourceHandle: 'router__tlm__output',
        targetHandle: 'target__tlm',
        type: 'default',
        label: 'TLM Map',
        markerStart: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(routerTlmToTargetTlm)
    })

    // Add Edges for TLM Enable
    for (const [tlmTargetName, enabled] of Object.entries(
      props.routerDetails[routerName].tlm_target_enabled,
    )) {
      if (tlmTargetName === 'UNKNOWN') {
        continue
      }
      if (!enabled) {
        continue
      }
      const cosmosTlmToRouterTlm = {
        id: `cosmos__${tlmTargetName}__router__${routerName}__tlm`,
        target: `router__${routerName}`,
        source: `cosmos__${tlmTargetName}`,
        sourceHandle: 'cosmos__tlm',
        targetHandle: 'router__tlm__input',
        type: 'default',
        label: 'TLM Enable',
        markerStart: {
          type: 'arrowclosed',
        },
      }
      edges.value.push(cosmosTlmToRouterTlm)
    }
  }

  // COSMOS node needs to be tall enough for all the handles

  targetNames.forEach((targetName, index) => {
    let x, y
    // Single target: place to the right
    x = 0
    y = index * (200 + 50)

    // Create cosmos node
    const cosmosNode = {
      id: `cosmos__${targetName}`,
      type: 'cosmos',
      position: { x, y },
      data: {
        label: targetName,
      },
      draggable: true,
    }
    nodes.value.push(cosmosNode)
  })

  // Interface Nodes
  let interfaceOrRouterIndex = 0
  let maxInterfaceOrRouterWidth = 200
  for (const interfaceName in interfaceDetails) {
    let writeProtocols =
      props.interfaceDetails[interfaceName].write_protocols || []
    let readProtocols =
      props.interfaceDetails[interfaceName].read_protocols || []

    // Calculate interface size based on protocol count
    const maxProtocols = Math.max(
      writeProtocols.length,
      readProtocols.length,
      1,
    )

    const interfaceWidth = Math.max(200, 80 + maxProtocols * 70) // Base width + protocol spacing
    if (interfaceWidth > maxInterfaceOrRouterWidth) {
      maxInterfaceOrRouterWidth = interfaceWidth
    }
    const interfaceHeight = 200 // Fixed height for two protocol rows

    // Create interface node (center) with dynamic size
    const interfaceNode = {
      id: `interface__${interfaceName}`,
      type: 'interface',
      position: { x: 400, y: (interfaceHeight + 50) * interfaceOrRouterIndex },
      data: {
        label: interfaceName,
        width: interfaceWidth,
        height: interfaceHeight,
      },
      draggable: true,
    }
    nodes.value.push(interfaceNode)
    interfaceOrRouterIndex += 1

    // Create write protocol nodes (horizontal row above)
    const startX = 50 // Left margin inside interface
    writeProtocols.forEach((protocol, index) => {
      let nameWithoutProtocol = protocol.name
      if (protocol.name.slice(-8) === 'Protocol') {
        nameWithoutProtocol = protocol.name.slice(0, -8)
      }
      const writeProtocolNode = {
        id: `write-protocol__interface__${interfaceName}__${index}`,
        type: 'write-protocol',
        position: {
          x: startX + index * 70, // Horizontal spacing
          y: 98, // Upper row
        },
        data: {
          index: index,
          interface: interfaceName,
          label: nameWithoutProtocol,
        },
        draggable: false,
        parentNode: `interface__${interfaceName}`,
        extent: 'parent',
      }
      nodes.value.push(writeProtocolNode)
    })

    // Create read protocol nodes (horizontal row below write protocols)
    readProtocols.forEach((protocol, index) => {
      let nameWithoutProtocol = protocol.name
      if (protocol.name.slice(-8) === 'Protocol') {
        nameWithoutProtocol = protocol.name.slice(0, -8)
      }
      const readProtocolNode = {
        id: `read-protocol__interface__${interfaceName}__${index}`,
        type: 'read-protocol',
        position: {
          x: startX + index * 70, // Horizontal spacing
          y: 148, // Lower row
        },
        data: {
          index: index,
          interface: interfaceName,
          label: nameWithoutProtocol,
        },
        draggable: false,
        parentNode: `interface__${interfaceName}`,
        extent: 'parent',
      }
      nodes.value.push(readProtocolNode)
    })
  }

  // Router Nodes
  for (const routerName in routerDetails) {
    let writeProtocols = props.routerDetails[routerName].write_protocols || []
    let readProtocols = props.routerDetails[routerName].read_protocols || []

    // Calculate interface size based on protocol count
    const maxProtocols = Math.max(
      writeProtocols.length,
      readProtocols.length,
      1,
    )

    const routerWidth = Math.max(200, 80 + maxProtocols * 70) // Base width + protocol spacing
    if (routerWidth > maxInterfaceOrRouterWidth) {
      maxInterfaceOrRouterWidth = routerWidth
    }
    const routerHeight = 200 // Fixed height for two protocol rows

    // Create router node (center) with dynamic size
    const routerNode = {
      id: `router__${routerName}`,
      type: 'router',
      position: { x: 400, y: (routerHeight + 50) * interfaceOrRouterIndex },
      data: {
        label: routerName,
        width: routerWidth,
        height: routerHeight,
      },
      draggable: true,
    }
    nodes.value.push(routerNode)
    interfaceOrRouterIndex += 1

    // Create write protocol nodes (horizontal row above)
    const startX = 50 // Left margin inside interface
    writeProtocols.forEach((protocol, index) => {
      let nameWithoutProtocol = protocol.name
      if (protocol.name.slice(-8) === 'Protocol') {
        nameWithoutProtocol = protocol.name.slice(0, -8)
      }
      const writeProtocolNode = {
        id: `write-protocol__router__${routerName}__${index}`,
        type: 'write-protocol',
        position: {
          x: startX + index * 70, // Horizontal spacing
          y: 98, // Upper row
        },
        data: {
          index: index,
          router: routerName,
          label: nameWithoutProtocol,
        },
        draggable: false,
        parentNode: `router__${routerName}`,
        extent: 'parent',
      }
      nodes.value.push(writeProtocolNode)
    })

    // Create read protocol nodes (horizontal row below write protocols)
    readProtocols.forEach((protocol, index) => {
      let nameWithoutProtocol = protocol.name
      if (protocol.name.slice(-8) === 'Protocol') {
        nameWithoutProtocol = protocol.name.slice(0, -8)
      }
      const readProtocolNode = {
        id: `read-protocol__router__${routerName}__${index}`,
        type: 'read-protocol',
        position: {
          x: startX + index * 70, // Horizontal spacing
          y: 148, // Lower row
        },
        data: {
          index: index,
          router: routerName,
          label: nameWithoutProtocol,
        },
        draggable: false,
        parentNode: `router__${routerName}`,
        extent: 'parent',
      }
      nodes.value.push(readProtocolNode)
    })
  }

  // Target Nodes
  targetNames.forEach((targetName, index) => {
    let x, y
    // Single target: place to the right
    x = 200 + 200 + maxInterfaceOrRouterWidth + 200
    y = index * (200 + 50)

    // Create target node
    const targetNode = {
      id: `target__${targetName}`,
      type: 'target',
      position: { x, y },
      data: {
        label: targetName,
      },
      draggable: true,
    }
    nodes.value.push(targetNode)
  })

  layoutNeeded = true
}

watch(
  () => props.interfaceDetails,
  async () => {
    if (props.interfaceDetails !== null) {
      updateFlowChart()
      nextTick(() => {
        layoutGraph('LR')
      })
    }
  },
  { immediate: true },
)

watch(
  () => props.routerDetails,
  async () => {
    if (props.routerDetails !== null) {
      updateFlowChart()
      nextTick(() => {
        layoutGraph('LR')
      })
    }
  },
  { immediate: true },
)
</script>

<template>
  <div class="interface-flow-chart">
    <VueFlow
      v-if="nodes.length > 0"
      :nodes="nodes"
      :edges="edges"
      :max-zoom="4"
      :min-zoom="0.01"
      class="vue-flow-container"
      elevate-edges-on-select
      :apply-default="false"
      @node-click="onNodeClick"
    >
      <Background pattern-color="#aaa" :gap="16" />
      <Controls>
        <ControlButton title="Reset" @click="layoutGraph('LR', true)">
          <svg width="16" height="16" viewBox="0 0 32 32">
            <path
              d="M18 28A12 12 0 1 0 6 16v6.2l-3.6-3.6L1 20l6 6l6-6l-1.4-1.4L8 22.2V16a10 10 0 1 1 10 10Z"
            />
          </svg>
        </ControlButton>
      </Controls>

      <template #node-interface="{ data }">
        <InterfaceNode :data="data" />
      </template>

      <template #node-router="{ data }">
        <RouterNode :data="data" />
      </template>

      <template #node-target="{ data }">
        <TargetNode :data="data" />
      </template>

      <template #node-cosmos="cosmosNodeProps">
        <CosmosNode v-bind="cosmosNodeProps" />
      </template>

      <template #node-write-protocol="{ data }">
        <WriteProtocolNode :data="data" />
      </template>

      <template #node-read-protocol="{ data }">
        <ReadProtocolNode :data="data" />
      </template>
    </VueFlow>

    <div v-else class="empty-state">
      <v-icon large color="grey">mdi-lan-disconnect</v-icon>
      <div class="text-grey mt-2">Nothing to show</div>
    </div>

    <!-- Details Dialog -->
    <v-dialog v-model="detailsDialog" max-width="80vw" max-height="80vh">
      <DetailsTable
        :mode="selectedMode"
        :details="selectedDetails"
        :read-protocol-index="selectedReadProtocolIndex"
        :write-protocol-index="selectedWriteProtocolIndex"
        @close="detailsDialog = false"
      />
    </v-dialog>
  </div>
</template>

<style>
/* import the necessary styles for Vue Flow to work */
@import '@vue-flow/core/dist/style.css';
@import '@vue-flow/controls/dist/style.css';
@import '@vue-flow/core/dist/theme-default.css';

.interface-flow-chart {
  height: 100%;
  width: 100%;
}

.vue-flow-container {
  height: 100%;
  width: 100%;
  background-color: rgb(23, 38, 53);
  border-radius: 4px;
}

.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: #6b7280;
}

.vue-flow__handle {
  height: 24px;
  width: 10px;
  background: #aaa;
  border-radius: 4px;
}

.vue-flow__edges path {
  stroke-width: 3;
}

.vue-flow__node {
  background-color: rgb(23, 38, 53);
}

.vue-flow__edges path {
  stroke-width: 2;
}
</style>

<style scoped></style>
