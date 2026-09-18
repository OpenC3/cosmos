# OpenC3 COSMOS Plugin

See the [OpenC3](https://openc3.com) documentation for all things OpenC3.

Update this comment with your own description.

## Getting Started

1. Edit the .gemspec file fields: name, summary, description, authors, email, and homepage
1. Update the LICENSE.md file with your company name

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

```
docker run -it -v `pwd`:/openc3/local:z -w /openc3/local docker.io/openc3inc/openc3-node sh
```

Windows:

```
docker run -it -v %cd%:/openc3/local -w /openc3/local docker.io/openc3inc/openc3-node sh
```

1. pnpm install --frozen-lockfile --ignore-scripts
1. rake build VERSION=1.0.0

## Continuous integration

`.github/workflows/` ships three GitHub Actions workflows that work as soon as
you push this plugin to GitHub. They call shared workflows from `OpenC3/.github`,
so the steps stay current without you updating anything here.

- **Unit Tests** - on every push and pull request. Runs Python tests in `tests/`
  or `test/` and Ruby specs in `spec/` or `specs/`. Whichever you don't have is
  skipped, so just add a test file.
- **Playwright** - on every push and pull request, plus weekly. Builds the gem,
  starts the latest COSMOS release in Docker, and installs the plugin through the
  Admin tool, which catches a `plugin.txt` that doesn't parse, a target that
  doesn't build, or a microservice that won't start. The weekly run is what tells
  you a new COSMOS release broke this plugin. Once you add targets, list them in
  `expected_targets` so the install is verified against them.
- **Release** - manual, from the Actions tab. Builds the gem, tags the commit and
  creates a GitHub release. Publishing to the OpenC3 App Store and to RubyGems is
  off until you add the matching secret and tick the box.

Adding a tool or a widget needs no change to any of these. All three build a
frontend with pnpm as soon as the plugin has a `package.json`.

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
