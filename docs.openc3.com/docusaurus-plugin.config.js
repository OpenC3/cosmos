// @ts-check
// Note: type annotations allow type checking and IDEs autocompletion

// Workaround to always use SHA256 to support FIPS mode
const crypto = require('crypto')
const crypto_orig_createHash = crypto.createHash
crypto.createHash = algorithm =>
  crypto_orig_createHash('sha256')

const {themes} = require('prism-react-renderer');
const lightCodeTheme = themes.nightOwlLight;
const darkCodeTheme = themes.nightOwl;

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'OpenC3 Docs',
  tagline: 'OpenC3 COSMOS Documentation',
  favicon: 'img/favicon.png',

  // Set the production url of your site here
  url: 'https://docs.openc3.com',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/tools/staticdocs/',
  trailingSlash: false,

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
  organizationName: 'OpenC3', // Usually your GitHub org/user name.
  projectName: 'cosmos', // Usually your repo name.

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'throw',

  // Even if you don't use internalization, you can use this field to set useful
  // metadata like html lang. For example, if your site is Chinese, you may want
  // to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  plugins: [
    [
      '@docusaurus/plugin-client-redirects',
      {
        redirects: [
          { to: '/docs/', from: '/docs/v5/', },
          { to: '/docs/tools', from: '/docs/v5/tools', },
          { to: '/docs/getting-started/installation', from: '/docs/v5/installation', },
          { to: '/docs/getting-started/gettingstarted', from: '/docs/v5/gettingstarted', },
          { to: '/docs/getting-started/upgrading', from: '/docs/v5/upgrading', },
          { to: '/docs/getting-started/requirements', from: '/docs/v5/requirements', },
          { to: '/docs/getting-started/podman', from: '/docs/v5/podman', },
          { to: '/docs/configuration/format', from: '/docs/v5/format', },
          { to: '/docs/configuration/plugins', from: '/docs/v5/plugins', },
          { to: '/docs/configuration/target', from: '/docs/v5/target', },
          { to: '/docs/configuration/command', from: '/docs/v5/command', },
          { to: '/docs/configuration/telemetry', from: '/docs/v5/telemetry', },
          { to: '/docs/configuration/interfaces', from: '/docs/v5/interfaces', },
          { to: '/docs/configuration/protocols', from: '/docs/v5/protocols', },
          { to: '/docs/configuration/table', from: '/docs/v5/table', },
          { to: '/docs/configuration/telemetry-screens', from: '/docs/v5/telemetry-screens', },
          { to: '/docs/configuration/ssl-tls', from: '/docs/v5/ssl-tls', },
          { to: '/docs/tools/cmd-tlm-server', from: '/docs/v5/cmd-tlm-server', },
          { to: '/docs/tools/limits-monitor', from: '/docs/v5/limits-monitor', },
          { to: '/docs/tools/cmd-sender', from: '/docs/v5/cmd-sender', },
          { to: '/docs/tools/script-runner', from: '/docs/v5/script-runner', },
          { to: '/docs/tools/packet-viewer', from: '/docs/v5/packet-viewer', },
          { to: '/docs/tools/tlm-viewer', from: '/docs/v5/tlm-viewer', },
          { to: '/docs/tools/tlm-grapher', from: '/docs/v5/tlm-grapher', },
          { to: '/docs/tools/data-extractor', from: '/docs/v5/data-extractor', },
          { to: '/docs/tools/data-viewer', from: '/docs/v5/data-viewer', },
          { to: '/docs/tools/bucket-explorer', from: '/docs/v5/bucket-explorer', },
          { to: '/docs/tools/table-manager', from: '/docs/v5/table-manager', },
          { to: '/docs/tools/handbooks', from: '/docs/v5/handbooks', },
          { to: '/docs/tools/calendar', from: '/docs/v5/calendar', },
          { to: '/docs/guides/bridges', from: '/docs/v5/bridges', },
          { to: '/docs/guides/cfs', from: '/docs/v5/cfs', },
          { to: '/docs/guides/custom-widgets', from: '/docs/v5/custom-widgets', },
          { to: '/docs/guides/little-endian-bitfields', from: '/docs/v5/little-endian-bitfields', },
          { to: '/docs/guides/local-mode', from: '/docs/v5/local-mode', },
          { to: '/docs/guides/logging', from: '/docs/v5/logging', },
          { to: '/docs/guides/monitoring', from: '/docs/v5/monitoring', },
          { to: '/docs/guides/performance', from: '/docs/v5/performance', },
          { to: '/docs/guides/raspberrypi', from: '/docs/v5/raspberrypi', },
          { to: '/docs/guides/scripting-api', from: '/docs/v5/scripting-api', },
          { to: '/docs/guides/script-writing', from: '/docs/v5/script-writing', },
          { to: '/docs/development/roadmap', from: '/docs/v5/roadmap', },
          { to: '/docs/development/developing', from: '/docs/v5/development', },
          { to: '/docs/development/testing', from: '/docs/v5/testing', },
          { to: '/docs/development/json-api', from: '/docs/v5/json-api', },
          { to: '/docs/development/streaming-api', from: '/docs/v5/streaming-api', },
          { to: '/docs/development/log-structure', from: '/docs/v5/log-structure', },
          { to: '/docs/development/host-install', from: '/docs/v5/host-install', },
          { to: '/docs/meta/contributing', from: '/docs/v5/contributing', },
          { to: '/docs/meta/philosophy', from: '/docs/v5/philosophy', },
          { to: '/docs/meta/xtce', from: '/docs/v5/xtce', },
        ],
      },
    ],
    require.resolve('docusaurus-lunr-search'),
  ],

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          // sidebarPath: require.resolve('./sidebars.js'),
          // Please change this to your repo.
          // Remove this to remove the "edit this page" links.
          editUrl:
            'https://github.com/OpenC3/cosmos/tree/main/docs.openc3.com/',
        },
        theme: {
          customCss: require.resolve('./src/css/custom.css'),
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      // Replace with your project's social card
      // image: 'img/docusaurus-social-card.jpg',
      navbar: {
        title: 'OpenC3 Docs',
        logo: {
          alt: 'OpenC3 Logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'docSidebar',
            sidebarId: 'defaultSidebar',
            position: 'left',
            label: 'Documentation',
          },
          {
            to: 'https://openc3.com/enterprise/',
            label: 'Enterprise',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Homepage',
            items: [
              {
                label: 'Home',
                to: 'https://openc3.com',
              },
            ],
          },
          {
            title: 'Docs',
            items: [
              {
                label: 'Documentation',
                to: '/docs',
              },
            ],
          },
          {
            title: 'Community',
            items: [
              {
                label: 'LinkedIn',
                href: 'https://www.linkedin.com/company/openc3',
              },
            ],
          },
          {
            title: 'More',
            items: [
              {
                label: 'GitHub',
                href: 'https://github.com/OpenC3/cosmos',
              },
              {
                label: 'Privacy',
                to: '/docs/privacy',
              },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} OpenC3, Inc.`,
      },
      prism: {
        theme: lightCodeTheme,
        darkTheme: darkCodeTheme,
        additionalLanguages: ['ruby', 'python', 'bash', 'diff', 'json'],
      },
      colorMode: {
        defaultMode: 'dark',
        disableSwitch: true,
        respectPrefersColorScheme: false,
      },
      tableOfContents: {
        minHeadingLevel: 2,
        maxHeadingLevel: 5,
      },
    }),
};

module.exports = config;
