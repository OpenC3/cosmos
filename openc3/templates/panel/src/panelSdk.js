// The Dashboards panel SDK: composables, option readers, formatting and
// building blocks shared with the built-in panels. Dashboards passes it to
// each panel's entry file when it loads the panel, so it's filled in before
// any panel component is set up. Shared by every panel in this plugin.
//
// https://docs.openc3.com/docs/guides/custom-panels
export const sdk = {}

export function setSdk(value) {
  Object.assign(sdk, value)
}
