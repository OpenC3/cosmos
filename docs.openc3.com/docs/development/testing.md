---
title: Testing COSMOS
description: Running the Playwright integration tests and unit tests
sidebar_custom_props:
  myEmoji: 📋
---

## Playwright

### Prerequesits

1. Install pnpm

   ```bash
   npm install --global pnpm@latest-10
   ```

1. Clone the COSMOS Playwright repo

   ```bash
   git clone https://github.com/OpenC3/cosmos-playwright
   ```

1. Install Playwright and dependencies

   ```bash
   cosmos-playwright % pnpm install
   ```

### Playwright Testing

1. Start COSMOS

   ```bash
   cosmos % openc3.sh start
   ```

1. Open COSMOS in your browser. At the login screen, set the password to "password".

1. Run tests (Note the --headed option visually displays tests, leave it off to run in the background)

   Tests are split into a group that runs in parallel and a group that runs serially. This is done to improve overall execution time.

   ```bash
   cosmos-playwright % pnpm test:parallel --headed
   cosmos-playwright % pnpm test:serial --headed
   ```

   You can run both groups together, but the --headed option will not apply to both groups:

   ```bash
   cosmos-playwright % pnpm test
   ```

1. Generate code coverage

   ```bash
   cosmos-playwright % pnpm coverage
   ```

Code coverage reports can be viewed at `openc3-playwright/coverage/index.html`

## Ruby Unit Tests

1. Navigate to **cosmos/openc3** folder. Run the command:

   ```bash
   cosmos/openc3 % rake build
   cosmos/openc3 % bundle exec rspec
   ```

Code coverage reports can be found at `cosmos/openc3/coverage/index.html`

## Python Unit Tests

1. Navigate to **cosmos/openc3/python** folder. Run the command:

   ```bash
   cosmos/openc3/python % python -m pip install poetry
   cosmos/openc3/python % poetry install
   cosmos/openc3/python % poetry run coverage run -m pytest
   cosmos/openc3/python % poetry run coverage html
   ```

Code coverage reports can be found at `cosmos/openc3/python/coverage/index.html`
