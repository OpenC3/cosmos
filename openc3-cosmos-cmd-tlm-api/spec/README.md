# Running Tests
## Simple
[This script](./run_tests.sh) should always work, but it will run all setup steps each time, even if they are not necessary.
```sh
./run_tests.sh
```

## Details
Once you have the environment set up, you can run the tests (the last step) without all of the setup steps each time.
1. **Environment**: Configure environment variables for OPENC3_DEVEL (local path to cosmos/openc3, for use of unreleased gem version) and RUBYGEMS_URL (any source for gems)
    ```sh
    export RUBYGEMS_URL=https://rubygems.org
    export OPENC3_DEVEL=/absolute/path/to/cosmos/openc3
    ```

1. **Install**: Install gems in `cosmos/` (root), `cosmos/openc3/`, and `cosmos/openc3-cosmos-cmd-tlm-api/`. Make sure that development gems are installed. See [bundler config docs](https://bundler.io/man/bundle-config.1.html) for details on configuring the development 3.
    ```sh
    bundle install
    ```

1. **Build**: From within the openc3 directory:
    ```sh
    bundle exec rake build
    ```

1. **Run tests**: From within `openc3-cosmos-cmd-tlm-api/` directory:
    ```sh
    bundle exec rspec
    ```
