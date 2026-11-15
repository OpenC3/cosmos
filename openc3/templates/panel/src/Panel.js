import { setSdk } from './panelSdk'
import <%= panel_name %> from './<%= panel_name %>.vue'

// The <%= panel_type %> panel type. Dashboards calls this with the panel SDK
// and adds the type it returns to the panel type picker. Dashboard files then
// use it like the built-in types:
//
//   PANEL <%= panel_type %> 0 0 3 3 "Title"
//     ITEM INST HEALTH_STATUS TEMP1
//     SETTING DECIMALS 2
//   END
export default (sdk) => {
  setSdk(sdk)
  return {
    label: '<%= panel_label %>',
    description: 'One telemetry value with its limits status',
    // Any Material Design Icon: https://pictogrammers.com/library/mdi/
    icon: 'mdi-puzzle-outline',
    component: <%= panel_name %>,
    // What the panel dialog edits: 'items', 'targets', 'command' or 'screen'
    content: 'items',
    maxItems: 1,
    // Width and height for a new panel, in grid cells
    defaults: { w: 3, h: 3 },
    // SETTINGs this panel understands. Each one parses, saves and shows in
    // the panel dialog; read it with sdk.option(panel, NAME).
    options: [
      {
        name: 'DECIMALS',
        type: 'number',
        label: 'Decimal places',
        default: null,
        min: 0,
        max: 10,
        help: 'Leave empty to use the item format',
      },
    ],
  }
}
