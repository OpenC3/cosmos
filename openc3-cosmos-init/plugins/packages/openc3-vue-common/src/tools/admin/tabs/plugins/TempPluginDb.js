/* TODO: implement API for real */

const pluginList = [
  {
    title: 'An awesome plugin',
    titleSlug: 'an-awesome-plugin',
    author: 'Totally Real Space Co.',
    authorSlug: 'totally-real-space',
    description: 'Short description that fits on two lines.',
    keywords: ['cosmos', 'plugin'],
    image: 'https://cdn.prod.website-files.com/646d451b4b3d75dd994b85bd/660dbb96f6470c6536bfd6be_forgec2.jpg',
    license: 'BSD',
    rating: 2.5,
    downloads: 12,
    verified: false,
    homepage: 'https://www.google.com',
    repository: 'https://github.com',
    gemUrl: 'https://rubygems.org/an-awesome-plugin.gem',
    gemSha: '9038o0450439850943850984305804398509348509843',
  },
  {
    title: 'Power Supply Adapter',
    titleSlug: 'power-supply-adapter',
    author: 'David Heinemeier Hansson',
    authorSlug: 'dhh',
    description: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
    keywords: ['power supply'],
    image: null,
    license: 'MIT',
    rating: 5,
    downloads: 42,
    verified: false,
    homepage: 'https://www.google.com',
    repository: 'https://github.com',
    gemUrl: 'https://rubygems.org/power-supply-adapter.gem',
    gemSha: '9038o0450439850943850984305804398509348509843',
  },
  {
    title: 'Calendar',
    titleSlug: 'calendar',
    author: 'OpenC3 Inc.',
    authorSlug: 'openc3',
    description: 'Calendar visualizes metadata, notes, and timeline information in one easy to understand place. Timelines allow for the simple execution of commands and scripts based on future dates and times.',
    image: 'https://docs.openc3.com/assets/images/blank_calendar-70e605942120937b862bd7039348229bab9af1f9c93d356ddbf401a3e8543c74.png',
    license: 'Commercial - Enterprise Only',
    rating: 4.5,
    downloads: 1337,
    verified: true,
    homepage: 'https://docs.openc3.com/docs/tools/calendar',
    repository: 'https://github.com/OpenC3/cosmos-enterprise/tree/main/openc3-cosmos-enterprise-init/plugins/packages/openc3-cosmos-tool-calendar',
    gemUrl: 'https://rubygems.org/cosmos-calendar.gem',
    gemSha: '9038o0450439850943850984305804398509348509843',
  },
  {
    title: 'Demo',
    titleSlug: 'demo',
    author: 'OpenC3 Inc.',
    authorSlug: 'openc3',
    description: 'This is the demo plugin',
    image: '/img/logo.png',
    license: 'i actually don\'t know lol',
    rating: 5,
    downloads: 9001,
    verified: true,
    homepage: 'https://docs.openc3.com',
    repository: 'https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-demo',
    gemUrl: 'https://rubygems.org/cosmos-demo.gem',
    gemSha: 'demosha256'
  }
]

const pluginApi = {
  getAll: function () {
    return pluginList
  },
  getBySha: function (hash) {
    const filtered = pluginList
      .filter((plugin) => plugin.gemSha.toLowerCase() === hash?.toLowerCase())
    if (filtered.length) return filtered[0]
    return null
  },
}

export default pluginApi
