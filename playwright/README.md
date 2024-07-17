# Testing OpenC3 with Playwright

NOTE: All commands are assumed to be executed from this (playwright) directory unless otherwise noted

1.  Start openc3

        OPENC3> openc3.bat start

1.  Open OpenC3 in your browser. It should take you to the login screen. Set the password to "password"

1.  Install testing dependencies with yarn

        playwright> yarn
        playwright> npx playwright install

1.  Generate the test plugins (must be located above this directory). If openc3.sh isn't in your path you might need to use an absolute or relative path to it.

        playwright> cd ..
        > openc3.sh cliroot generate plugin PW_TEST
        > cd openc3-cosmos-pw-test
        openc3-pw-test> openc3.sh cliroot generate target PW_TEST
        openc3-pw-test> openc3.sh cliroot rake build VERSION=1.0.0
        openc3-pw-test> cp openc3-cosmos-pw-test-1.0.0.gem openc3-cosmos-pw-test-1.0.1.gem

1.  Set Enterprise if running against OpenC3 COSMOS Enterprise

        playwright> set ENTERPRISE=1

1.  Open playwright and run tests

        playwright> yarn playwright test --headed --project=chromium

1.  Run with the playwright UI

        playwright> yarn playwright test --ui --project=chromium

1.  Enable the playwright inspector / debugger with

        playwright> set PWDEBUG=1
        playwright> yarn playwright test --headed --project=chromium

1.  _[Optional]_ Fix istanbul/nyc coverage source lookups (use `fixlinux` if not on Windows).
    Tests will run successfully without this step and you will get coverage statistics, but line-by-line coverage won't work.

        playwright> yarn fixwindows

1.  Create code coverage

        playwright> yarn coverage

Code coverage reports can be viewed at [playwright/coverage/index.html](./coverage/index.html)
