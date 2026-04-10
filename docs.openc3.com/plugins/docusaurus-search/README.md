# docusaurus-search

A local Docusaurus plugin that provides client-side full-text search using [MiniSearch](https://github.com/lucatonber/minisearch). It replaces external search services (Algolia, etc.) with a fully self-contained, offline-capable search experience.

## How It Works

### Build Time

During `docusaurus build`, the plugin's `postBuild` hook:

1. Resolves every Docusaurus route to its rendered HTML file on disk (`utils.js` &rarr; `getFilePaths`)
2. Spawns worker threads (`html-to-doc.mjs`) to parse each HTML file with [cheerio](https://github.com/cheeriojs/cheerio)
3. Each worker extracts search documents — one per page title and one per section heading (h2/h3/h4) — with their text content, keywords from `<meta>` tags, and optional version labels
4. The main thread adds each document to a MiniSearch index and collects the raw document data
5. Writes two output files (with cache-busting filenames) to the build directory:
   - `search-doc-{guid}.json` — the raw search documents array plus plugin options
   - `search-index-{guid}.json` — the serialized MiniSearch index

A webpack alias (`@generated/mini-search.client`) is also created so the runtime code can import MiniSearch.

### Runtime

When the user interacts with the search bar:

1. `index.jsx` lazy-loads the search doc and index JSON files, plus `DocSearch.js` and `algolia.css`
2. `DocSearch` creates a `MiniSearchAdapter` (`mini-search.js`) from the serialized index
3. On each keystroke (debounced), MiniSearch runs a prefix search and returns ranked hits
4. Hits are formatted through `DocSearch.formatHits` using utility functions (`utils.js`) that group results by hierarchy level (lvl0/lvl1) and apply highlight markup
5. Results are rendered into a dropdown using Mustache-style templates (`templates.js` via `mini-mustache.js`)
6. When a result is selected, client-side navigation is performed via React Router, and the `HighlightSearchResults` component marks matching terms on the destination page

## Architecture

```
src/
├── index.js                    # Plugin entry — Docusaurus lifecycle hooks
├── utils.js                    # Build utilities (route resolution, client codegen)
├── html-to-doc.mjs             # Worker thread — HTML parsing with cheerio
└── theme/SearchBar/
    ├── index.jsx               # React search bar component (lazy loading, keyboard shortcut)
    ├── DocSearch.js             # Search controller (input handling, dropdown, keyboard nav)
    ├── mini-search.js           # MiniSearch adapter (query, hit formatting, snippets)
    ├── mini-mustache.js         # Minimal Mustache template compiler (no dependencies)
    ├── templates.js             # HTML templates for search suggestions and empty state
    ├── utils.js                 # Hit formatting utilities (groupBy, merge, highlight)
    ├── HighlightSearchResults.jsx  # Highlights matching terms on the target page
    ├── algolia.css              # Dropdown and suggestion styling
    └── styles.css               # Search icon responsive styles
```

## Dependencies

| Dependency | Purpose |
|---|---|
| [minisearch](https://www.npmjs.com/package/minisearch) | Full-text search index (build and runtime) |
| [cheerio](https://www.npmjs.com/package/cheerio) | HTML parsing in worker threads at build time |
| [clsx](https://www.npmjs.com/package/clsx) | Conditional CSS class joining in the React component |
| [prop-types](https://www.npmjs.com/package/prop-types) | Runtime prop validation for the search bar |

The plugin also depends on Docusaurus APIs (`@docusaurus/router`, `@docusaurus/useDocusaurusContext`, `@docusaurus/useGlobalData`, `@docusaurus/useIsBrowser`) provided by the host site.

## Docusaurus Integration

### Registration

The plugin is registered in `docusaurus.config.js` as a local plugin:

```js
plugins: [
  [
    require.resolve("./plugins/docusaurus-search/src/index.js"),
    {
      maxHits: "25",
      // other options...
    },
  ],
],
```

### Lifecycle Hooks

The plugin implements these Docusaurus plugin hooks:

- **`getThemePath()`** — registers `src/theme/` so the `SearchBar` component overrides the default theme slot
- **`configureWebpack()`** — generates the `@generated/mini-search.client` module on first webpack build
- **`contentLoaded()`** — exposes the cache-busted JSON filenames via `setGlobalData` so the runtime component can fetch them
- **`postBuild()`** — parses all built HTML pages and writes the search index files

### Plugin Options

| Option | Type | Description |
|---|---|---|
| `maxHits` | string/number | Maximum search results to display (default: 5) |
| `excludeRoutes` | string[] | Glob patterns for routes to exclude from the index |
| `includeRoutes` | string[] | Glob patterns for routes to include (allowlist mode) |
| `indexBaseUrl` | boolean | Whether to index the base URL page (default: false) |
| `highlightResult` | boolean | Enable term highlighting on the destination page |
| `fields` | object | Override boost values for title, content, and keywords |
| `stopWords` | string[] | Words to exclude from the index |
| `excludeTags` | string[] | HTML tag names whose sections should be excluded |
| `disableVersioning` | boolean | Ignore doc version labels in search results |
| `assetUrl` | string | Base URL for fetching search index files (defaults to `baseUrl`) |

## Origin

This plugin is a fork of [docusaurus-lunr-search](https://github.com/praveenn77/docusaurus-lunr-search), rewritten to use MiniSearch instead of Lunr.js, with the Algolia autocomplete UI replaced by a custom dropdown implementation. The CSS class names retain the `algolia-docsearch-*` prefix for compatibility with the existing stylesheet.
