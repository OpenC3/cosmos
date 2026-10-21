---
name: new-tool
description: Scaffold a new COSMOS custom tool plugin and set up live development against a running COSMOS (plugin generator, tool generator, one-time install, vite watch build + dev server, single-spa import-map override). Use when the user wants to create or start developing a new custom tool.
argument-hint: <PluginName> "<Tool Name>" [parent-dir] [vue|react|angular|svelte]
---

# Develop a new COSMOS tool

Scaffold a tool plugin with the COSMOS CLI generators, install it once so
COSMOS registers the tool, then serve the tool locally so a running COSMOS
(http://localhost:2900) loads your local build in place of the installed copy.

## Inputs

Parse `$ARGUMENTS` for:

1. **Plugin name** (for example `sss-data`). The generator adds the
   `openc3-cosmos-` prefix and converts `_` to `-`.
2. **Tool name**: the display name, which can include spaces (for example
   `"Mission Planner"`). The generator makes the folder name by lowercasing it and
   removing spaces and dashes (`missionplanner`). Call that `<toolname>` below.
   It must not clash with a built-in tool folder (`cmdsender`, `cmdtlmserver`,
   `scriptrunner`, `tlmviewer`, `tlmgrapher`, `dataviewer`, `dataextractor`,
   `limitsmonitor`, `packetviewer`, `bucketexplorer`, `handbooks`,
   `tablemanager`, `admin`, `base`, `iframe`). If it does, both tools use the
   same `/tools/<toolname>` route and bucket folder. Ask the user for a
   different name.
3. **Parent directory** (optional): where the plugin folder is created.
   Defaults to the parent of this cosmos repo, so the plugin sits beside it.
4. **Framework** (optional): `vue` (default), `react`, `angular` or `svelte`.
   This skill is written for Vue; the other templates use different build
   tooling, so check their `package.json` scripts before following steps 4-5.

If the plugin or tool name is missing, ask for it. Don't make one up.

`COSMOS` below means the absolute path of this cosmos repo (the one holding
`openc3.sh`). `openc3.sh cli` runs the CLI in a container with the current
directory mounted, so run it by absolute path from the target directory. The
containers must be built (`./openc3.sh build`). Steps 1-2 don't need COSMOS
running; step 3 onward does.

`openc3.sh cli` runs `docker compose run -it`, which fails in a non-interactive
shell with `cannot attach stdin to a TTY-enabled container because stdin is not
a terminal`. Wrap each CLI call in `script` to give it a pseudo-terminal:

```bash
script -q /dev/null $COSMOS/openc3.sh cli generate ... < /dev/null
```

## Steps

### 1. Generate the plugin

```bash
cd <parent-dir>
$COSMOS/openc3.sh cli generate plugin <PluginName>
```

This creates `<parent-dir>/openc3-cosmos-<plugin-name>/`. If the directory
already exists, the generator aborts. Stop and ask the user what to do; don't
delete anything.

### 2. Generate the tool

```bash
cd <parent-dir>/openc3-cosmos-<plugin-name>
$COSMOS/openc3.sh cli generate tool '<Tool Name>'
```

Use `tool_react`, `tool_angular` or `tool_svelte` instead of `tool` for
another framework. For Vue this creates `src/App.vue`, `src/main.js`,
`src/router.js`, `src/tools/<toolname>/<toolname>.vue`, `package.json`,
`vite.config.js`, `eslint.config.mjs`, `jsconfig.json` and
`pnpm-workspace.yaml`, and appends to `plugin.txt`:

```
TOOL <toolname> "<Tool Name>"
  INLINE_URL main.js
  ICON mdi-file-cad-box
```

Change the `ICON` to any [MDI icon](https://pictogrammers.com/library/mdi/)
if the user wants. If a `package.json` already exists, the generator skips it
and you have to merge the dependencies by hand.

### 3. Install, build and load the plugin once

From the plugin directory:

```bash
pnpm install
```

The generated `pnpm-workspace.yaml` has no `allowBuilds` section. pnpm 11
then fails with `ERR_PNPM_IGNORED_BUILDS` for esbuild and @parcel/watcher, and
writes `set this to true or false` placeholders into the file. Every later
`pnpm` script repeats the failure, because pnpm runs `pnpm install` before the
command. Set both to `false`, as in
`openc3-cosmos-init/plugins/pnpm-workspace.yaml`, which explains why neither
build script is needed:

```yaml
allowBuilds:
  '@parcel/watcher': false
  esbuild: false
```

Then run `pnpm install` again; it should finish without errors.

Unlike a widget, a tool must be installed before the override works. The
navigation drawer (`AppNav.vue` in openc3-vue-common) only calls single-spa's
`registerApplication` for tools that the `/openc3-api/tools` list returns, so
an uninstalled tool has no route and no `@openc3/tool-<toolname>` import-map
entry to override. Build and load the gem (COSMOS must be running):

```bash
rake build VERSION=1.0.0
script -q /dev/null $COSMOS/openc3.sh cli load openc3-cosmos-<plugin-name>-1.0.0.gem < /dev/null
```

`rake build` runs `pnpm run build`, then `gem build`, then
`openc3cli validate`. If `openc3cli` isn't on the host it prints `Install the
openc3 gem to validate!`; the gem is still built, so ignore that. Instead of
`cli load`, the user can upload the `.gem` in the Admin Plugins tab.

You only do this once. Reinstall only when `plugin.txt` changes (new name,
icon, extra `TOOL` lines and so on); code changes are picked up through the
override.

### 4. Start the build watcher and dev server

Start this long-running command with `run_in_background: true`:

```bash
pnpm serve
```

`serve` is `vite build --watch --mode dev-server`. After each rebuild, the
`devServerPlugin` from `@openc3/js-common/viteDevServerPlugin` kills and
respawns a plain `vite` server on `server.port` (2999 in `vite.config.js`).
That server serves the project root, so the bundle is at
`http://localhost:2999/tools/<toolname>/main.js` (the `build.outDir` is
`tools/<toolname>`).

- The spawned `vite` has no `--strictPort` and its output isn't shown. If
  port 2999 is taken (for example, by a widget's preview server), it quietly
  picks the next free port. Check with `lsof -nP -iTCP:2999 -sTCP:LISTEN`
  before starting; if it's busy, change `server.port` in `vite.config.js`
  and use that port in step 5.
- Check that it's served once the first build finishes:
  `curl -sI http://localhost:2999/tools/<toolname>/main.js` should return 200.
- Vite's default CORS policy allows `localhost` origins, so COSMOS on
  `localhost:2900` can fetch the bundle.

### 5. Override the tool URL in the browser (the user does this)

You can't run this yourself, so give the user the snippet with the names
filled in. Tell them to open COSMOS at `http://localhost:2900`, open the
DevTools console, paste it, and refresh:

```js
localStorage.setItem('devtools', true)
localStorage.setItem(
  'import-map-override:@openc3/tool-<toolname>',
  'http://localhost:2999/tools/<toolname>/main.js',
)
```

How it works: the cmd-tlm-api `ToolsController#importmap` maps
`@openc3/tool-<toolname>` to `/tools/<toolname>/main.js`, and single-spa loads
the tool with `System.import('@openc3/tool-<toolname>')`. import-map-overrides
replaces that entry with the local URL. Instead of the snippet, the user can
set only `devtools`, refresh, click the `{...}` button in the bottom right,
find `@openc3/tool-<toolname>`, and paste the local URL there. To remove the
override, reset it in that panel or call `localStorage.removeItem(...)` with
the same key.

Then open the tool from the navigation drawer, or go to
`http://localhost:2900/tools/<toolname>`.

## Development loop

Save a file, wait for the watcher to rebuild and respawn the server, then
refresh the page. There's no hot module reload. Tell the user to turn on
"Disable cache" in the DevTools Network tab so they don't get a stale bundle.

Run `pnpm lint` before committing; CI style rules match the core tools.

When the tool is done, rebuild and reinstall it with a new version:
`rake build VERSION=1.0.1`, then upload the `.gem` in the Admin Plugins tab or
run `$COSMOS/openc3.sh cli load <gem>`. After that, remove the override.

## Report back

Finish with the plugin path, the tool URL (`http://localhost:2900/tools/<toolname>`),
the local bundle URL, the filled-in console snippet, and the ID of the
background task so the user can stop it.
