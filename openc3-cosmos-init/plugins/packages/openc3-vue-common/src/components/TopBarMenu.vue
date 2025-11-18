<template>
  <v-menu v-model="menuOpen">
    <template #activator="{ props }">
      <v-btn
        v-bind="props"
        variant="outlined"
        class="mx-1 menu-button"
        :text="menu.label"
        :data-test="formatDT(`${title} ${menu.label}`)"
      >
        <template #append>
          <v-icon class="menu-button-icon"> mdi-menu-down </v-icon>
        </template>
      </v-btn>
    </template>
    <v-list>
      <template v-for="(option, j) in menu.items">
        <v-divider v-if="option.divider" :key="j + '-divider'" />
        <div
          v-else-if="option.subMenu && option.subMenu.length > 0"
          :key="j + '-submenu'"
        >
          <v-menu :key="j" open-on-hover location="right">
            <template #activator="{ props }">
              <v-list-item v-bind="props" :key="j" :disabled="option.disabled">
                <template v-if="option.icon" #prepend>
                  <v-icon :disabled="option.disabled">
                    {{ option.icon }}
                  </v-icon>
                </template>
                <v-list-item-title
                  v-if="!option.radio && !option.checkbox"
                  :style="
                    'cursor: pointer;' + (option.disabled ? 'opacity: 0.2' : '')
                  "
                >
                  {{ option.label }}
                </v-list-item-title>
                <template #append>
                  <v-icon> mdi-chevron-right </v-icon>
                </template>
              </v-list-item>
            </template>
            <v-list>
              <v-list-item
                v-for="(submenu, k) in option.subMenu"
                :key="k"
                :prepend-icon="submenu.icon"
                @click="emits('submenu-click', submenu)"
              >
                <v-list-item-title>{{ submenu.label }}</v-list-item-title>
              </v-list-item>
            </v-list>
          </v-menu>
        </div>
        <v-radio-group
          v-else-if="option.radioGroup"
          :key="j + '-radio-group'"
          class="ma-0 pa-0"
          density="compact"
          hide-details
          :model-value="option.value"
          @update:model-value="option.command"
        >
          <v-list-item
            v-for="(choice, k) in option.choices"
            :key="k + '-choice'"
          >
            <v-list-item-action class="list-action">
              <v-radio
                color="secondary"
                :label="choice.label"
                :value="choice.value"
                density="compact"
                hide-details
              />
            </v-list-item-action>
          </v-list-item>
        </v-radio-group>
        <v-list-item
          v-else
          :key="j + '-list'"
          :disabled="option.disabled"
          :data-test="formatDT(`${title} ${menu.label} ${option.label}`)"
          @click="option.command(option)"
        >
          <template v-if="option.icon" #prepend>
            <v-icon :icon="option.icon" :disabled="option.disabled"></v-icon>
          </template>
          <v-list-item-action v-if="option.checkbox" class="list-action">
            <v-checkbox
              v-model="option.checked"
              :label="option.label"
              color="secondary"
              density="compact"
              hide-details
            />
          </v-list-item-action>
          <v-list-item-title
            v-if="!option.radio && !option.checkbox"
            :style="
              'cursor: pointer;' + (option.disabled ? 'opacity: 0.2' : '')
            "
          >
            {{ option.label }}
          </v-list-item-title>
        </v-list-item>
      </template>
    </v-list>
  </v-menu>
</template>

<script setup>
defineProps({
  menu: { type: Object, required: true },
  title: { type: String, required: true },
})
const emits = defineEmits(['submenu-click'])

/**
 * Convert the string to a standard data-test format
 * @param {string} string
 */
function formatDT(string) {
  return string.replaceAll(' ', '-').toLowerCase()
}
</script>
