# OpenC3 COSMOS Plugin

See the [OpenC3](https://openc3.com) documentation for all things OpenC3.

Update this comment with your own description.

## Getting Started

1. Edit the .gemspec file fields: name, summary, description, authors, email, and homepage
1. Update the LICENSE.md file with your company name
<% if @@language == 'py' -%>
1. Install [uv](https://docs.astral.sh/uv/getting-started/installation/) to manage the plugin's Python dependencies

## Python dependencies with uv

The plugin's Python dependencies are declared in `pyproject.toml` and locked in `uv.lock`.
Both files are packaged into the gem automatically, and COSMOS reads them when the plugin is installed.

### Adding dependencies

```sh
uv add requests                 # runtime dependency, installed into COSMOS with the plugin
uv add --group dev pytest-mock  # development only, never installed into COSMOS
```

`uv add` updates both `pyproject.toml` and `uv.lock`. Commit both files.

`uv lock` resolves `pyproject.toml` and writes `uv.lock` without installing anything. `uv sync` does the
same when the lock is stale, then installs into `.venv`. Either works after editing `pyproject.toml` by hand;
commit the updated `uv.lock`.

COSMOS installs a locked plugin with `uv sync --frozen`, which installs exactly what `uv.lock` records and never
relocks, so a stale lock ships stale dependencies. `uv lock --check` fails if the lock is out of date.

### How COSMOS installs them

- **With `uv.lock`** (recommended): COSMOS runs `uv sync --frozen --no-dev`. Every install gets the same
  versions, downloaded from the URLs recorded in the lock.
- **Without `uv.lock`**: COSMOS resolves the dependencies at install time against the PyPI URL set in
  Admin Console -> Settings, so versions can change from one install to the next.

The `dev` dependency group is never installed into COSMOS.

### Developing locally

```sh
uv sync --group dev           # create .venv with runtime and dev dependencies
uv run --group dev pytest     # run tests; lib/ is on the import path
uv run --group dev ruff check # lint
uv run --group dev ruff format
uv run --group dev ty check   # type check
```

A plain `uv sync` installs only the runtime dependencies, matching what COSMOS installs.

The plugin itself is not installed into `.venv`: COSMOS puts `lib/` on the Python path instead, and pytest and ty
are configured to do the same. Anything else needs `lib/` on the path to import `<%= package_name %>`:

```
PYTHONPATH=lib uv run python my_script.py
```

uv picks any installed Python that satisfies `requires-python`. To develop against the same version COSMOS
runs, pin it locally with `uv python pin 3.12`, which writes a `.python-version` file.

The `openc3` dev dependency provides the COSMOS Python API for your editor, tests and `ty`. Pin it to the
COSMOS version you deploy to so they see the same API, e.g. `uv add --group dev "openc3==X.Y.Z"`.

### Where to put Python code

Put Python code shared across the plugin in `lib/<%= package_name %>/`, never directly in `lib/`.

COSMOS adds the `lib/` directory of every installed plugin to the Python path. If two plugins both ship
`lib/helpers.py`, `import helpers` loads whichever one Python finds first, and the other can't be imported
at all. A module directly in `lib/` can also hide an installed package of the same name, such as `requests`.
The `<%= package_name %>` package is named after this plugin, so its modules can't collide.

Import from the package:

```python
from <%= package_name %>.helpers import Helper
```

Reference its files by path in plugin configuration, e.g. `INTERFACE MY_INT <%= package_name %>/my_interface.py`.

### Updating dependencies

```
uv lock --upgrade-package requests  # upgrade one package
uv lock --upgrade                   # upgrade everything
```

### Private package indexes

See the comments in the `[tool.uv]` section of `pyproject.toml`. If the COSMOS PyPI URL setting points at
anything other than public PyPI, COSMOS ignores the plugin's own index settings when it resolves, so a
package published only to your private index must also be served by that index, or be locked in `uv.lock`.
<% end -%>

## Building non-tool / widget plugins

1. <Path to COSMOS installation>/openc3.sh cli rake build VERSION=X.Y.Z (or openc3.bat for Windows)
   - VERSION is required
   - gem file will be built locally

## Building tool / widget plugins using a local Ruby/Node/pnpm/Rake Environment

1. pnpm install --frozen-lockfile --ignore-scripts
1. rake build VERSION=1.0.0

## Building tool / widget plugins using Docker and the openc3-node container

If you don’t have a local node environment, you can use our openc3-node container to build custom tools and custom widgets

Mac / Linux:

```sh
docker run -it -v `pwd`:/openc3/local:z -w /openc3/local docker.io/openc3inc/openc3-node sh
```

Windows:

```sh
docker run -it -v %cd%:/openc3/local -w /openc3/local docker.io/openc3inc/openc3-node sh
```

1. pnpm install --frozen-lockfile --ignore-scripts
1. rake build VERSION=1.0.0

## Installing into OpenC3 COSMOS

1. Go to the OpenC3 Admin Tool, Plugins Tab
1. Click the install button and choose your plugin.gem file
1. Fill out plugin parameters
1. Click Install

## Contributing

We encourage you to contribute to OpenC3!

Contributing is easy.

1. Fork the project
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Before any contributions can be incorporated we do require all contributors to agree to a Contributor License Agreement

This protects both you and us and you retain full rights to any code you write.

## License

This OpenC3 plugin is released under the MIT License. See [LICENSE.md](LICENSE.md)
