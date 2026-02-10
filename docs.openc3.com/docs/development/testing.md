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

1. Clone the COSMOS repo

   ```bash
   git clone https://github.com/OpenC3/cosmos
   ```

1. Install Playwright and dependencies

   ```bash
   cd cosmos/playwright
   cosmos/playwright % ./playwright.sh install-playwright
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
   cosmos/playwright % pnpm test:parallel --headed
   cosmos/playwright % pnpm test:serial --headed
   ```

   You can run both groups together, but the --headed option will not apply to both groups:

   ```bash
   cosmos/playwright % pnpm test
   ```

1. _[Optional]_ Fix istanbul/nyc coverage source lookups (use `fixwindows` if not on Linux).

   Tests will run successfully without this step and you will get coverage statistics, but line-by-line coverage won't work.

   ```bash
   cosmos/playwright % pnpm fixlinux
   ```

1. Generate code coverage

   ```bash
   cosmos/playwright % pnpm coverage
   ```

Code coverage reports can be viewed at `cosmos/playwright/coverage/index.html`

## Ruby Unit Tests

1. Navigate to **cosmos/openc3** folder. Run the command:

   ```bash
   cosmos/openc3 % rake build
   cosmos/openc3 % bundle exec rspec
   ```

Code coverage reports can be found at `cosmos/openc3/coverage/index.html`

## Python Unit Tests

### Using Just (Recommended)

1. Navigate to **cosmos/openc3/python** folder and run tests with coverage:

   ```bash
   cosmos/openc3/python % just test-cov-html
   ```

   See all available commands:

   ```bash
   cosmos/openc3/python % just
   ```

   Common commands:
   - `just test` - Run all tests
   - `just test-cov` - Run tests with coverage report
   - `just test-cov-html` - Run tests with HTML coverage report
   - `just lint` - Check code quality
   - `just format` - Format code
   - `just verify` - Format, lint, and test (pre-commit check)

### Manual Testing

1. Navigate to **cosmos/openc3/python** folder and install dependencies:

   ```bash
   cosmos/openc3/python % uv sync
   ```

2. Run tests with coverage:

   ```bash
   cosmos/openc3/python % uv run coverage run -m pytest
   cosmos/openc3/python % uv run coverage html
   ```

Code coverage reports can be found at `cosmos/openc3/python/htmlcov/index.html`
