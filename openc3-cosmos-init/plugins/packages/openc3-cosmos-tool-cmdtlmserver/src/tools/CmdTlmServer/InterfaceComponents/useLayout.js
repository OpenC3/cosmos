import dagre from '@dagrejs/dagre'
import { Position, useVueFlow } from '@vue-flow/core'
import { ref } from 'vue'

/**
 * Composable to run the layout algorithm on the graph.
 * It uses the `dagre` library to calculate the layout of the nodes and edges.
 */
export function useLayout() {
  const { findNode } = useVueFlow()

  const graph = ref(new dagre.graphlib.Graph())

  const previousDirection = ref('LR')

  function layout(nodes, edges, direction) {
    // we create a new graph instance, in case some nodes/edges were removed, otherwise dagre would act as if they were still there
    const dagreGraph = new dagre.graphlib.Graph()

    graph.value = dagreGraph

    dagreGraph.setDefaultEdgeLabel(() => ({}))

    const isHorizontal = direction === 'LR'
    dagreGraph.setGraph({ rankdir: direction })

    previousDirection.value = direction

    for (const node of nodes) {
      // Protocol nodes are positioned relative to their parent interface / router
      // node and move with it, so they must not take part in the layout
      if (node.parentNode) {
        continue
      }

      // if you need width+height of nodes for your layout, you can use the dimensions property of the internal node (`GraphNode` type)
      const graphNode = findNode(node.id)

      dagreGraph.setNode(node.id, {
        width: graphNode.dimensions.width,
        height: graphNode.dimensions.height,
      })
    }

    for (const edge of edges) {
      dagreGraph.setEdge(edge.source, edge.target)
    }

    dagreGraph.graph().ranksep = 200
    dagre.layout(dagreGraph)

    // set nodes with updated positions
    return nodes.map((node) => {
      const nodeWithPosition = dagreGraph.node(node.id)

      if (!nodeWithPosition) {
        return node
      }

      return {
        ...node,
        targetPosition: isHorizontal ? Position.Left : Position.Top,
        sourcePosition: isHorizontal ? Position.Right : Position.Bottom,
        // dagre returns the center of the node but Vue Flow positions nodes by
        // their top left corner. Without this the right / bottom half of every
        // node eats into the separation dagre allocated, so wide nodes (an
        // interface with many protocols) overlap their neighbors.
        position: {
          x: nodeWithPosition.x - nodeWithPosition.width / 2,
          y: nodeWithPosition.y - nodeWithPosition.height / 2,
        },
      }
    })
  }

  return { graph, layout, previousDirection }
}
