---
title: Testing COSMOS
---

## Playwright

### Prerequesits

1. Install Yarn

   ```bash
   npm install --global yarn
   ```

1. Clone the COSMOS Playwright repo

   ```bash
   git clone https://github.com/OpenC3/cosmos-playwright
   ```

1. Install Playwright and dependencies

   ```bash
   cosmos-playwright % yarn install
   ```

### Playwright Testing

1. Start COSMOS

   ```bash
   cosmos % openc3.sh start
   ```

1. Open COSMOS in your browser. At the login screen, set the password to "password".

1. Run tests (Note the --headed option visually displays tests, leave it off to run in the background)

   ```bash
   cosmos-playwright % yarn playwright test --project=chromium --headed
   ```

1. _[Optional]_ Fix istanbul/nyc coverage source lookups (use `fixwindows` if not on Linux).

   Tests will run successfully without this step and you will get coverage statistics, but line-by-line coverage won't work.

   ```bash
   cosmos-playwright % yarn fixlinux
   ```

1. Generate code coverage

   ```bash
   cosmos-playwright % yarn coverage
   ```

Code coverage reports can be viewed at `openc3-playwright/coverage/index.html`

## Unit Tests

1. Navigate to **cosmos/openc3** folder. Run the command:

   ```bash
   cosmos/openc3 % rake build
   cosmos/openc3 % bundle exec rspec
   ```

Code coverage reports can be found at `cosmos/openc3/coverage/index.html`
