// @ts-check
import { computed } from 'vue'

export function useContainerHeight() {
  const containerHeight = computed(() => {
    // if openc3-tool-base/src/App.vue <v-main /> style is changed from using min-height to height, this may become unnecessary
    const header = document.getElementById('openc3-app-toolbar')
    const footer = document.getElementById('footer')
    const main = document.getElementsByTagName('main')[0]
    const mainDiv = main.children[0]
    const mainDivStyles = getComputedStyle(mainDiv)
    const headerHeight = header ? header.offsetHeight + Number.parseFloat(getComputedStyle(header).marginTop) : 0
    const footerHeight = footer ? footer.offsetHeight + Number.parseFloat(getComputedStyle(footer).marginBottom) : 0
    return `calc(100vh - ${headerHeight + footerHeight + Number.parseInt(mainDivStyles.paddingTop) + Number.parseInt(mainDivStyles.paddingBottom)}px)`
  })

  return containerHeight
}
