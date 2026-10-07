---
name: new-widget
description: Scaffold a new COSMOS custom TlmViewer widget plugin and set up live development against a running COSMOS (plugin generator, widget generator, vite watch build + preview server, devtools import-map override). Use when the user wants to create or start developing a new custom widget.
argument-hint: <PluginName> <NameWidget> [parent-dir]
---

# Develop a new COSMOS widget

Scaffold a widget plugin with the COSMOS CLI generators, then serve the widget
locally so a running COSMOS (http://localhost:2900) loads it in place of the
installed copy. You don't need to install the plugin while you're developing.

## Inputs

Parse `$ARGUMENTS` for:

1. **Plugin name** (for example `sss-data`). The generator adds the
   `openc3-cosmos-` prefix and converts `_` to `-`.
2. **Widget name**: CapitalCase ending in `Widget` (for example `SummitWidget`).
   The generator rejects anything else. Screens use the name without `Widget`,
   in uppercase (`SUMMIT`).
3. **Parent directory** (optional): where the plugin folder is created.
   Defaults to the parent of this cosmos repo, so the plugin sits beside it.

If the plugin or widget name is missing, ask for it. Don't make one up.

`COSMOS` below means the absolute path of this cosmos repo (the one holding
`openc3.sh`). `openc3.sh cli` runs the CLI in a container with the current
directory mounted, so run it by absolute path from the target directory. The
containers must be built (`./openc3.sh build`). They don't have to be running.

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

### 2. Generate the widget

```bash
cd <parent-dir>/openc3-cosmos-<plugin-name>
$COSMOS/openc3.sh cli generate widget <NameWidget>
```

This creates `src/<NameWidget>.vue`, `package.json`, `vite.config.js` and
`pnpm-workspace.yaml`, and adds `WIDGET <Name>` to `plugin.txt`.

### 3. Install, then start the build watcher and preview server

From the plugin directory:

```bash
pnpm install
```

The generated `pnpm-workspace.yaml` has no `allowBuilds` section. pnpm 11
then fails with `ERR_PNPM_IGNORED_BUILDS` for esbuild and @parcel/watcher, and
writes `set this to true or false` placeholders into the file. Every later
`pnpm vite ...` repeats the failure, because pnpm runs `pnpm install` before
the command. Set both to `false`, as in
`openc3-cosmos-init/plugins/pnpm-workspace.yaml`, which explains why neither
build script is needed:

```yaml
allowBuilds:
  '@parcel/watcher': false
  esbuild: false
```

Then run `pnpm install` again; it should finish without errors.

Then start these two long-running commands, each with
`run_in_background: true`:

```bash
pnpm vite build --watch
```

```bash
pnpm vite preview --port 2999 --strictPort
```

- `vite preview` serves `build.outDir` (`tools/widgets/<NameWidget>`) at the
  root, so the bundle is at `http://localhost:2999/<NameWidget>.umd.min.js`.
  Start the preview server only after the first build has written that file.
- `--strictPort` makes the server fail instead of quietly switching ports. If
  port 2999 is taken (for example, by another widget's preview server), pick
  another port and use it in step 4.
- Vite's default CORS policy allows `localhost` origins, so COSMOS on
  `localhost:2900` can fetch the bundle.
- Check that it's served:
  `curl -sI http://localhost:2999/<NameWidget>.umd.min.js` should return 200.

### 4. Override the widget URL in the browser (the user does this)

You can't run this yourself, so give the user the snippet with the names
filled in. Tell them to open COSMOS at `http://localhost:2900`, open the
DevTools console, paste it, and refresh:

```js
localStorage.setItem('devtools', true)
localStorage.setItem(
  'import-map-override:http://localhost:2900/tools/widgets/<NameWidget>/<NameWidget>.umd.min.js',
  'http://localhost:2999/<NameWidget>.umd.min.js',
)
```

How it works: TlmViewer's `DynamicWidget` (in openc3-vue-common) loads
`${window.location.origin}/tools/widgets/<NameWidget>/<NameWidget>.umd.min.js`
through SystemJS. SystemJS also applies import-map entries keyed by full URLs,
so this override sends that request to the local preview server. If COSMOS is
on a different host or port, change the key's origin to match. To remove the
override, delete the entry from the `{...}` devtools panel or call
`localStorage.removeItem(...)` with the same key.

### 5. Give the user a test screen

The default template uses the `VWidget` mixin, which needs
`TARGET PACKET ITEM [TYPE]`. If the item is missing, it crashes with
`TypeError: Cannot read properties of undefined (reading 'includes')`. Give the
user a screen they can paste into TlmViewer's screen editor:

```
SCREEN AUTO AUTO 1.0
<NAME> INST HEALTH_STATUS TEMP1
```

`<NAME>` is the widget name without `Widget`, in uppercase. The widget doesn't
need to be installed: any keyword that isn't a built-in widget is loaded
through `DynamicWidget`. For a widget that doesn't show a telemetry item, use
the `Widget` mixin instead of `VWidget`.

## Development loop

Save a file, wait for the watcher to rebuild, then refresh TlmViewer. There's
no hot reload. Tell the user to turn on "Disable cache" in the DevTools
Network tab so they don't get a stale bundle.

When the widget is done, build and install the plugin for real:
`pnpm build`, then `rake build VERSION=1.0.0`, then upload the `.gem` in the
Admin Plugins tab or run `$COSMOS/openc3.sh cli load <gem>`. After that, remove
the override.

## Report back

Finish with the plugin path, the preview URL, the filled-in console snippet,
the test screen, and the IDs of the two background tasks so the user can stop
them.
