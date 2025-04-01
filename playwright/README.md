# Testing OpenC3 with Playwright

NOTE: All commands are assumed to be executed from this (playwright) directory unless otherwise noted

1.  Start openc3

        OPENC3> openc3.bat start

1.  Open OpenC3 in your browser. It should take you to the login screen. Set the password to "password"

1.  Install testing dependencies with yarn

        playwright> yarn
        playwright> yarn playwright install

1.  Generate the test plugins (must be located above this directory). If openc3.sh isn't in your path you might need to use an absolute or relative path to it.

        playwright> cd ..
        > openc3.sh cliroot generate plugin PW_TEST
        > cd openc3-cosmos-pw-test
        openc3-pw-test> openc3.sh cliroot generate target PW_TEST
        openc3-pw-test> openc3.sh cliroot rake build VERSION=1.0.0
        openc3-pw-test> cp openc3-cosmos-pw-test-1.0.0.gem openc3-cosmos-pw-test-1.0.1.gem

## Running the tests

Tests are split into a parallel group and a serial group. This is done to lower overall execution time. Yarn scripts `yarn test:parallel` and `yarn test:serial` are provided to run each group individually. With these scripts, you can pass additional arguments such as `--ui` (see examples below).

There is also a yarn script `yarn test` which will run the parallel group, followed by the serial group. However, due to limitations in yarn, additional arguments will only be passed to the last group (serial).

These yarn scripts always pass the `--project=chromium` argument to both test groups. The script `yarn test:keycloak` is provided to run both test groups with `--project=keycloak`, but if you want to pass any other value to this argument, you will have to build the whole playwright command yourself, e.g.:

```bash
playwright> yarn playwright test ./tests/**/*.p.spec.ts --headed --project=firefox || yarn playwright test ./tests/**/*.s.spec.ts --headed --project=firefox --workers=1
```

Note the `--workers=1` passed to the serial (`*.s.spec.ts`) group. If you omit this argument, you will get very flaky test results from this group since Playwright defaults to running tests in parallel.

The following examples use the parallel group, but these apply to the serial group as well.

1.  Open playwright and run tests. The first example is running against Open Source, the second against Enterprise.

        playwright> yarn test:parallel --headed
        playwright> ENTERPRISE=1 yarn test:parallel --headed

1.  Playback a trace file. Note that the Github 'OpenC3 Playwright Tests' action stores the trace under the Summary link. Click Details next to the 'OpenC3 Playwright Tests' then Summary in the top left. Scroll down and download the playwright artifact. Unzip it and copy the files into the playwright/test-results directory. Then playback the trace to help debug.

        playwright> yarn playwright show-trace /test-results/<NAME OF TEST>/trace.zip

1.  Run with the playwright UI

        playwright> yarn test:parallel --ui

1.  Enable the playwright inspector / debugger with

        playwright> set PWDEBUG=1
        playwright> yarn test:parallel --headed

1.  _[Optional]_ Fix istanbul/nyc coverage source lookups (use `fixlinux` if not on Windows).
    Tests will run successfully without this step and you will get coverage statistics, but line-by-line coverage won't work.

        playwright> yarn fixwindows

1.  Create code coverage

        playwright> yarn coverage

Code coverage reports can be viewed at [playwright/coverage/index.html](./coverage/index.html)
