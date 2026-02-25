---
title: Roadmap
description: COSMOS roadmap now and into the future
sidebar_custom_props:
  myEmoji: 🗺️
---

Please read the release notes on the [Releases](https://github.com/OpenC3/cosmos/releases) page to learn about current functionality.

Our roadmap is captured via Github [Milestones](https://github.com/OpenC3/cosmos/milestones). We have major milestones (7.0, 8.0, etc) and minor milestones (7.1, 7.2, etc) that incorporate new functionality, enhancements, bug fixes, and dependency updates. Note that we also release patch releases (6.10.4) that incorporate only minor enhancements, bug fixes, and dependency updates but these are not milestoned.

## Monthly Releases

We are dedicated to monthly releases that update dependencies and close CVEs. This ensures that COSMOS stays current with the latest security patches and library updates.

## Language and Runtime Support

Our Ruby and Python client APIs support the currently supported versions of each language:

- **Ruby**: We support versions in normal maintenance and security maintenance as defined by the [Ruby Maintenance Branches](https://www.ruby-lang.org/en/downloads/branches/).
- **Python**: We support versions in bugfix and security status as defined by the [Python Release Cycle](https://devguide.python.org/versions/).

Our Docker containers are built on [Alpine Linux](https://alpinelinux.org/releases/) base images. The versions of Ruby and Python available in our containers are dependent on what is packaged in the Alpine releases. Our current Alpine version is [3.22](https://alpinelinux.org/posts/Alpine-3.22.0-released.html) which uses Ruby 3.4 and Python 3.12.

## Github Issues

We prioritize bugs and customer requests in our Github [issues](https://github.com/OpenC3/cosmos/issues) list. If you're an OpenC3 customer, please reach out at [support@openc3.com](mailto:support@openc3.com) and let us know what issues you need prioritized.
