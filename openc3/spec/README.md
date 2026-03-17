# OPENC3 TESTS

## Environment

```sh
export OPENC3_DEVEL=\path\to\cosmos\openc3
export RUBYGEMS_URL=https://rubygems.org
```

## Build

```sh
bundle install

rake build
```

## Run the test

From within the openc3 directory in the openc3 repo... aka `openc3/openc3` run `bundle exec rspec --color` or `bundle exec rake build spec`
